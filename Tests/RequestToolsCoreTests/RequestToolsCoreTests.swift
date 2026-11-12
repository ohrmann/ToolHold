import Testing
@testable import RequestToolsCore
@Test func requestIssueIsSafe(){#expect(RequestIssue("Unsupported profile").message == "Unsupported profile")}

import Foundation
@Test func shellLiteralProfile() throws {
    let t=try CurlTokenizer.tokenize(#"curl 'https://example.com' -H "X-Test: a\"b" --data-raw $'line\n\u00e9'"#)
    #expect(t.last?.value == "line\né")
    #expect(try CurlTokenizer.tokenize("curl '' a'bc'\"de\"").map(\.value)==["curl","","abcde"])
    for s in ["curl $(whoami)","curl \"$TOKEN\"","curl x | cat","curl x;echo bad",#"curl $'\xff'"#,#"curl $'\0'"#,"curl 'unterminated"] {#expect(throws:RequestIssue.self){try CurlTokenizer.tokenize(s)}}
    let source="curl 'https://example.com/🐱' -H 'X-Test: é'"
    for token in try CurlTokenizer.tokenize(source){#expect(NSMaxRange(token.range)<=source.utf16.count)}
}
@Test func curlBodyAndHeaders() throws {
    let r=try CurlProcessor.parse(#"curl 'https://example.com/a?q=%2F&q=+' -d 'a=1' -d 'b=2' -H 'X-List: a' -H 'X-List: b'"#)
    #expect(r.method=="POST");#expect(r.body=="a=1&b=2");#expect(r.headers.filter{$0.name=="X-List"}.count==2)
    #expect(r.url=="https://example.com/a?q=%2F&q=+")
    let raw=try CurlProcessor.parse(#"curl https://example.com --data-raw '@text'"#)
    #expect(raw.body=="@text");#expect(!raw.needsValues)
    #expect(try CurlProcessor.parse("curl https://example.com --data-binary @file").needsValues)
    let json=try CurlProcessor.parse(#"curl https://example.com --json '{"x":' --json '9007199254740993}'"#)
    #expect(json.body == #"{"x":9007199254740993}"#)
    #expect(try CurlProcessor.parse("curl https://example.com -G --data-urlencode 'q=a b'").url == "https://example.com?q=a%20b")
    for s in ["curl https://example.com --insecure","curl https://a.com https://b.com","curl https://a.com -d x -F a=b","curl https://a.com -b cookies.txt"] {#expect(throws:RequestIssue.self){try CurlProcessor.parse(s)}}
}
@Test func allRequestEmitters() throws {
    let r=try CurlProcessor.parse(#"curl 'https://example.com/a' -H 'Authorization: Bearer secret-token' --json '{"message":"é🐱 $value"}'"#)
    for language in RequestLanguage.allCases {
        let result=try RequestEmitters.generate(r,language:language)
        #expect(result.needsValues);#expect(!result.code.contains("secret-token"));#expect(result.code.contains("REPLACE_WITH_AUTHORIZATION"))
        #expect(try RequestEmitters.generate(r,language:language,includeSecrets:true).code.contains("secret-token"))
    }
    let get=try CurlProcessor.parse("curl https://example.com -X GET -d x")
    #expect(throws:RequestIssue.self){try RequestEmitters.generate(get,language:.javascript)}
    let duplicate=try CurlProcessor.parse("curl https://example.com -H 'X: 1' -H 'X: 2'")
    #expect(throws:RequestIssue.self){try RequestEmitters.generate(duplicate,language:.swift)}
    #expect(try RequestEmitters.generate(duplicate,language:.java).code.contains("builder.header(\"X\", \"2\")"))
}
@Test func multipartLiteralAndPlaceholder() throws {
    let literal=try CurlProcessor.parse("curl https://example.com --form-string 'field=@literal' -F 'x=hello;type=text/plain'")
    #expect(!literal.needsValues);#expect(literal.parts[0].value=="@literal")
    let file=try CurlProcessor.parse("curl https://example.com -F 'upload=@private.png;filename=image.png;type=image/png'")
    #expect(file.needsValues);#expect(file.parts[0].filename=="image.png")
    #expect(try RequestEmitters.generate(file,language:.swift).needsValues)
    #expect(try RequestEmitters.generate(file,language:.swift).code.contains("REPLACE_WITH_BASE64_REQUEST_BODY"))
    #expect(throws:RequestIssue.self){try CurlProcessor.parse("curl https://example.com -F x=@a,@b")}
}
@Test func connectionProfiles() throws {
    let fixtures:[(ConnectionProfile,String)]=[
        (.postgresURI,"postgresql://user:p%40ss@[::1]:5432,db.example:5433/name?sslmode=require&customToken=x+y"),
        (.postgresKV,#"host=localhost password='a b\'c' dbname=x host=other"#),
        (.sqlServer,#"Server=localhost;Password="a;b=""c";Database=test;UID=user;"#),
        (.mysql,"jdbc:mysql://localhost:3306/db?user=alice&password=s%2Becret"),
        (.mongo,"mongodb://user:pass@a:27017,b:27018/db?replicaSet=rs"),
        (.mongo,"mongodb+srv://example.com/db"),
        (.redis,"rediss://user:secret@localhost:6379/0")]
    for (profile,source) in fixtures {
        let d=try ConnectionProcessor.parse(source,profile:profile)
        #expect(!d.fields.isEmpty)
        let redacted=try d.redacted();#expect(!redacted.contains("secret"));#expect(!redacted.contains("customToken=x+y"))
        for f in d.fields{#expect(NSMaxRange(f.range)<=source.utf16.count)}
        if let f=d.fields.first(where:{$0.sensitive}){
            let edit=try d.editing(f.id,value:"a;b='🦄+%");#expect(edit.fields.first(where:{$0.id==f.id})?.value=="a;b='🦄+%")
        }
    }
}
@Test func connectionFailClosedAndDuplicates() throws {
    for source in ["postgresql://host:abc/db","mongodb+srv://host:123/db","redis://host/-1","postgresql://user:%FF@host/db","jdbc:mysql://a,b/db"]{#expect(throws:RequestIssue.self){try ConnectionProcessor.parse(source,profile:.automatic)}}
    let d=try ConnectionProcessor.parse("Password='a;b';Pwd=x;Server=local;Custom=x",profile:.sqlServer)
    #expect(d.fields.count==4);#expect(try !d.redacted().contains("a;b"))
    let edited=try d.editing(1,value:"new");#expect(edited.fields[0].value=="a;b");#expect(edited.fields[1].value=="new")
    #expect(throws:RequestIssue.self){try ConnectionProcessor.parse("Server=local;Password=x",profile:.automatic)}
}
@MainActor @Test func revisionsAndMemoryOnly() async throws {
    let w=CurlWorkspace();w.input="curl https://example.com";w.run();w.input="curl malformed"
    try await Task.sleep(for:.milliseconds(80));#expect(w.result==nil)
    let c=ConnectionWorkspace();c.input="redis://localhost/0";c.run();c.input="changed";try await Task.sleep(for:.milliseconds(80));#expect(c.document==nil)
    #expect(CurlWorkspace().input.isEmpty);#expect(ConnectionWorkspace().input.isEmpty);#expect(CurlWorkspace().masked)
}
@Test func unsafeQueryAndShellLines() throws {
 #expect(throws:RequestIssue.self){try CurlProcessor.parse("curl https://example.com -G -d '%ZZ'")}
 #expect(throws:RequestIssue.self){try CurlTokenizer.tokenize("curl https://example.com\n-H 'X: y'")}
 #expect(try CurlTokenizer.tokenize("curl \\\n'https://example.com'").count==2)
 #expect(throws:RequestIssue.self){try ConnectionProcessor.parse("host=localhost port=invalid",profile:.postgresKV)}
}
@MainActor @Test func requestPreferencesNeverContainSecrets() async throws {
 let name="request-settings-"+UUID().uuidString,d=UserDefaults(suiteName:name)!;defer{d.removePersistentDomain(forName:name)}
 let c=CurlWorkspace(defaults:d);c.input="curl https://example.com -H 'Authorization: synthetic-secret'";c.language = .java;c.includeSecrets=true
 let connection=ConnectionWorkspace(defaults:d);connection.input="Password=synthetic-secret";connection.profile = .sqlServer
 let values=d.persistentDomain(forName:name)!
 #expect(Set(values.keys)==["curl.target","connection.profile"])
 #expect(!String(describing:values).contains("synthetic-secret"))
 #expect(!CurlWorkspace(defaults:d).includeSecrets);#expect(ConnectionWorkspace(defaults:d).input.isEmpty)
}

@Test func redactAllIncludesNumericPortsAndDatabase() throws {
 let source="redis://alice:private@db.example:6379/4?custom=token"
 let d=try ConnectionProcessor.parse(source,profile:.redis)
 let redacted=try d.redacted(hideAll:true)
 for secret in ["alice","private","db.example","6379","/4","token"]{#expect(!redacted.contains(secret))}
 #expect(redacted.contains(":REDACTED/REDACTED"))
}

@Test func requestTimeoutCompressionAndExplicitRedirectPolicy() throws {
 let r=try CurlProcessor.parse("curl https://example.com --compressed")
 let python=try RequestEmitters.generate(r,language:.python).code
 #expect(python.contains("Accept-Encoding") && python.contains("gzip, deflate"))
 #expect(try RequestEmitters.generate(r,language:.swift).code.contains("timeoutIntervalForRequest = .greatestFiniteMagnitude"))
 let custom=try CurlProcessor.parse("curl https://example.com -L -X POST -d x")
 #expect(custom.methodWasExplicit)
 for language in RequestLanguage.allCases{#expect(throws:RequestIssue.self){try RequestEmitters.generate(custom,language:language)}}
 let noRedirect=try CurlProcessor.parse("curl https://example.com -L --max-redirs 0")
 #expect(try RequestEmitters.generate(noRedirect,language:.csharp).code.contains("AllowAutoRedirect = false"))
}
