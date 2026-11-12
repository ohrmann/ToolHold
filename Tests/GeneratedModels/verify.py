#!/usr/bin/env python3
"""Compile production-generator artifacts exported by the explicit Swift fixture test.

No installation, network access or application input. Requires pinned local dev tools.
Usage: python3 Tests/GeneratedModels/verify.py --artifacts /tmp/toolbox-models-artifacts
       --tools /tmp/toolbox-models-tools [--language swift] [--fixture Basic]
"""
import argparse
import decimal
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def run(args, cwd=None, env=None, timeout=90):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError("Command failed: " + str(args[0]) + "\n" + result.stdout[-9000:])
    return result.stdout


def semantic_equal(expected, actual):
    # DTO Optional/POJO profiles deliberately conflate null/missing, never other kinds.
    if expected is None:
        return actual is None
    if isinstance(expected, bool):
        return isinstance(actual, bool) and expected == actual
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(
            semantic_equal(value, actual.get(key)) for key, value in expected.items()
        ) and all(key in expected or value is None for key, value in actual.items())
    if isinstance(expected, list):
        return isinstance(actual, list) and len(expected) == len(actual) and all(
            semantic_equal(a, b) for a, b in zip(expected, actual))
    if isinstance(expected, decimal.Decimal):
        return isinstance(actual, decimal.Decimal) and expected == actual
    return type(expected) is type(actual) and expected == actual


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--tools', type=Path, required=True)
    parser.add_argument('--language')
    parser.add_argument('--fixture')
    parser.add_argument('--start-at', help='Resume unfinished matrix at language/fixture, inclusive')
    args = parser.parse_args()
    records = json.loads((args.artifacts / 'manifest.json').read_text())
    records = [r for r in records if (not args.language or r['language'] == args.language)
               and (not args.fixture or r['fixture'] == args.fixture)]
    if args.start_at:
        index = next(i for i, r in enumerate(records) if r['language'] + '/' + r['fixture'] == args.start_at)
        records = records[index:]
    if not records:
        raise RuntimeError('No matching exported production fixtures')
    kotlin = json.loads((args.tools / 'kotlin.json').read_text()) if any(r['language'] == 'kotlin' for r in records) else None
    # Use an explicit toolchain or the developer's environment, never a personal path.
    jdk = None
    if any(r['language'] == 'java' for r in records):
        if os.environ.get('MODELS_JDK_BIN'):
            jdk = Path(os.environ['MODELS_JDK_BIN'])
        elif os.environ.get('JAVA_HOME'):
            jdk = Path(os.environ['JAVA_HOME']) / 'bin'
        elif shutil.which('javac'):
            jdk = Path(shutil.which('javac')).parent
        else:
            raise RuntimeError('Install JDK 17 and set JAVA_HOME or MODELS_JDK_BIN; no tools are downloaded.')
    maven = Path.home() / '.m2/repository/com/fasterxml/jackson/core'
    jackson = [maven / p for p in [
        'jackson-databind/2.22.2/jackson-databind-2.22.2.jar',
        'jackson-core/2.22.2/jackson-core-2.22.2.jar',
        'jackson-annotations/2.22/jackson-annotations-2.22.jar']]
    environment = dict(os.environ, DOTNET_CLI_HOME=str(args.tools / 'dotnet-home'),
                       DOTNET_CLI_TELEMETRY_OPTOUT='1', DOTNET_NOLOGO='1')
    versions = {}
    for language in dict.fromkeys(r['language'] for r in records):
        if language == 'swift': versions[language] = run(['swiftc', '--version']).strip()
        elif language == 'typeScript': versions[language] = run(['node', args.tools / 'package/bin/tsc', '--version']).strip()
        elif language == 'cSharp': versions[language] = run(['dotnet', '--version'], env=environment).strip() + '; target net8.0, C#12; runtime roll-forward Major'
        elif language == 'java': versions[language] = run([jdk / 'java', '-version']).strip() + '; Jackson 2.22.2/annotations 2.22'
        elif language == 'kotlin': versions[language] = 'compiler/plugin 2.2.20; kotlinx.serialization 1.9.0; JVM17'
    for record in records:
        language, name, root = record['language'], record['fixture'], record['root']
        folder = args.artifacts / language / name
        source = folder / record['file']
        data = (folder / 'sample.json').read_text()
        text = None
        if language == 'swift':
            (folder / 'main.swift').write_text('import Foundation\nlet data = try Data(contentsOf: URL(fileURLWithPath: "sample.json"))\n'
                f'let model = try JSONDecoder().decode({root}.self, from: data)\n'
                'let encoded = try JSONEncoder().encode(model)\nprint(String(decoding: encoded, as: UTF8.self))\n')
            run(['swiftc', source, folder / 'main.swift', '-o', folder / 'runner'])
            text = run([folder / 'runner'], cwd=folder)
        elif language == 'typeScript':
            negative = ('// @ts-expect-error unknown requires narrowing before use\nconst invalid: string = sample;\n'
                        if record['rootType'] == 'unknown' else
                        '// @ts-expect-error a function is not compatible with the inferred shape\n'
                        f'const invalid: {root} = () => 1;\n')
            (folder / 'check.ts').write_text(f"import type {{ {root} }} from './{root}';\n"
                f'const sample: {root} = {data};\nvoid sample;\n'
                + negative)
            run(['node', args.tools / 'package/bin/tsc', '--noEmit', '--strict', '--exactOptionalPropertyTypes',
                 '--noUncheckedIndexedAccess', source, folder / 'check.ts'])
            text = run(['node', '-e', "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('sample.json','utf8'))))"], cwd=folder)
        elif language == 'cSharp':
            (folder / 'Fixture.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
                '<OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><LangVersion>12</LangVersion>'
                '<Nullable>enable</Nullable><RollForward>Major</RollForward></PropertyGroup></Project>')
            (folder / 'Program.cs').write_text('using System; using System.IO; using System.Text.Json;\n'
                f'var model = {root}Json.Decode(File.ReadAllText("sample.json"));\n'
                'Console.WriteLine(JsonSerializer.Serialize(model));\n')
            run(['dotnet', 'build', folder / 'Fixture.csproj', '--nologo', '-v:q'], env=environment)
            text = run(['dotnet', folder / 'bin/Debug/net8.0/Fixture.dll'], cwd=folder, env=environment)
        elif language == 'java':
            (folder / 'Runner.java').write_text('import java.nio.file.*; import com.fasterxml.jackson.databind.ObjectMapper;\n'
                'public class Runner { public static void main(String[] args) throws Exception {\n'
                f'var model = {root}.fromJson(Files.readString(Path.of("sample.json")));\n'
                'System.out.println(new ObjectMapper().disable(com.fasterxml.jackson.databind.SerializationFeature.FAIL_ON_EMPTY_BEANS).writeValueAsString(model)); }}\n')
            classpath = ':'.join(str(p) for p in jackson)
            run([jdk / 'javac', '-cp', classpath, source, folder / 'Runner.java'])
            text = run([jdk / 'java', '-cp', str(folder) + ':' + classpath, 'Runner'], cwd=folder)
        elif language == 'kotlin':
            (folder / 'Runner.kt').write_text('import kotlinx.serialization.json.Json\n'
                'import kotlinx.serialization.encodeToString\nimport java.io.File\n'
                f'fun main() {{ val json = Json {{ ignoreUnknownKeys = true; explicitNulls = true }}; '
                f'val model = json.decodeFromString<{root}>(File("sample.json").readText()); '
                'println(json.encodeToString(model)) }\n')
            run([kotlin['java'], '-cp', ':'.join(kotlin['compiler']), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                 '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', ':'.join(kotlin['libs']),
                 '-Xplugin=' + kotlin['plugin'], '-d', folder / 'classes', source, folder / 'Runner.kt'])
            text = run([kotlin['java'], '-cp', str(folder / 'classes') + ':' + ':'.join(kotlin['libs']), 'RunnerKt'], cwd=folder)
        expected = json.loads(data, parse_int=decimal.Decimal, parse_float=decimal.Decimal)
        actual = json.loads(text.strip(), parse_int=decimal.Decimal, parse_float=decimal.Decimal)
        if not semantic_equal(expected, actual):
            raise RuntimeError(f'{language}/{name}: decoded/encoded values or keys changed')
        print(f'PASS {language}/{name}: production code compile + values/keys', flush=True)
    hashes = {}
    files = ([args.tools / 'typescript.tgz'] if 'typeScript' in versions else [])
    if 'java' in versions: files += jackson
    if kotlin: files += [Path(p) for p in kotlin['compiler'] + kotlin['libs'] + [kotlin['plugin']]]
    for file in files:
        hashes[file.name] = hashlib.sha256(file.read_bytes()).hexdigest()
    report = {'versions': versions, 'sha256': hashes, 'passed': len(records), 'records': records}
    (args.artifacts / ('verification-' + (args.language or 'all') + '.json')).write_text(json.dumps(report, indent=2))
    print(f'PASS {len(records)} fixture/profile combinations. Manifest written.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
