import Foundation
public enum RequestLanguage:String,CaseIterable,Sendable,Codable,Identifiable {
    case swift="Swift",javascript="JavaScript",typescript="TypeScript",python="Python",csharp="C#",java="Java",kotlin="Kotlin"
    public var id:String{rawValue}
    public var fileExtension:String {switch self{case .swift:"swift";case .javascript:"mjs";case .typescript:"ts";case .python:"py";case .csharp:"cs";case .java:"java";case .kotlin:"kt"}}
}
public struct GeneratedRequest:Sendable {public let code:String,issues:[String],needsValues:Bool}
public enum RequestEmitters {
    public static func generate(_ original:HTTPRequestSpec,language:RequestLanguage,includeSecrets:Bool=false)throws->GeneratedRequest {
        var r=original,needs=original.needsValues,issues=original.issues
        r.headers=r.headers.map{h in if !includeSecrets && ["authorization","proxy-authorization","cookie"].contains(h.name.lowercased()) && !h.removed{needs=true;return RequestHeader(name:h.name,value:"REPLACE_WITH_"+h.name.uppercased().replacingOccurrences(of:"-",with:"_"),removed:false)};return h}
        if r.headers.contains(where:{$0.removed}) {throw RequestIssue("Unsupported for selected target: explicit removal of client-generated headers cannot be guaranteed. Remove that option or use another request representation.")}
        let groups=Dictionary(grouping:r.headers,by:{$0.name.lowercased()})
        if [.swift,.javascript,.typescript,.python].contains(language),groups.contains(where:{$0.value.count>1}) {throw RequestIssue("Unsupported for selected target: this API combines repeated header fields. Choose Java, Kotlin or C# to retain the header list.")}
        if [.javascript,.typescript].contains(language),["GET","HEAD"].contains(r.method.uppercased()),r.body != nil || !r.parts.isEmpty {throw RequestIssue("Fetch forbids a GET/HEAD body. The method was not changed.")}
        if r.connectTimeout != nil && [.swift,.javascript,.typescript,.csharp].contains(language){throw RequestIssue("Unsupported for selected target: a separate connection timeout is not exposed by this API.")}
        if r.maxRedirects != nil && [.javascript,.typescript,.java,.kotlin].contains(language){throw RequestIssue("Unsupported for selected target: custom redirect count requires a dedicated transport loop.")}
        if r.followRedirects && (r.methodWasExplicit || !["GET","HEAD","POST"].contains(r.method.uppercased())){throw RequestIssue("Explicit/custom-method redirect semantics require a dedicated loop; remove -X or choose no redirects for this target.")}
        if r.compressed && language == .python && !r.headers.contains(where:{$0.name.lowercased()=="accept-encoding"}){r.headers.append(RequestHeader(name:"Accept-Encoding",value:"gzip, deflate",removed:false))}
        if !r.parts.isEmpty {try multipart(&r)}
        let q:(String)->String = { literal($0,language:language) }
        let body=r.body.map{r.needsValues ? "REPLACE_WITH_BASE64_REQUEST_BODY":Data($0.utf8).base64EncodedString()}
        if r.needsValues{issues.append("Provide Base64 of the complete request body in REPLACE_WITH_BASE64_REQUEST_BODY. For multipart, retain the boundary shown in Content-Type. No file content was read.")}
        let timeout=r.totalTimeout ?? 0,redirects=r.maxRedirects ?? 50
        let comment=language == .python ? "#" : "//"
        let preamble="\(comment) Generated locally. Review before running; this tool never sends requests.\n\(comment) \(needs ? "NEEDS VALUES: replace placeholders." : "HTTP client controls wire headers and URL normalization.")\n\(comment) Body and URL may contain secrets; header redaction is not full anonymization.\n"
        var code=""
        switch language {
        case .swift:
            code="""
            import Foundation

            final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
                private var redirects = 0
                func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
                    redirects += 1
                    completionHandler(\(r.followRedirects ? "redirects <= \(redirects) ? request : nil" : "nil"))
                }
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = \(timeout>0 ? String(timeout):".greatestFiniteMagnitude")
            \(timeout>0 ? "configuration.timeoutIntervalForResource = \(timeout)" : "configuration.timeoutIntervalForResource = .greatestFiniteMagnitude")
            let policy = RedirectPolicy()
            let session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
            var request = URLRequest(url: URL(string: \(q(r.url)))!)
            request.httpMethod = \(q(r.method))
            \(r.headers.map{"request.addValue(\(q($0.value)), forHTTPHeaderField: \(q($0.name)))"}.joined(separator:"\n"))
            \(body.map{"request.httpBody = Data(base64Encoded: \(q($0)))!"} ?? "")
            let (data, response) = try await session.data(for: request)
            print((response as? HTTPURLResponse)?.statusCode ?? 0)
            print(String(decoding: data, as: UTF8.self))
            session.invalidateAndCancel()
            """
        case .javascript,.typescript:
            code="""
            // Node 20+ Fetch. Browser header/CORS restrictions differ.
            const headers = new Headers();
            \(r.headers.map{"headers.append(\(q($0.name)), \(q($0.value)));"}.joined(separator:"\n"))
            const options\(language == .typescript ? ": RequestInit" : "") = {
              method: \(q(r.method)), headers,
              redirect: \(q(r.followRedirects ? "follow":"manual")),
              \(timeout>0 ? "signal: AbortSignal.timeout(\(Int(timeout*1000)))," : "")
              \(body.map{"body: Buffer.from(\(q($0)), 'base64'),"} ?? "")
            };
            const response = await fetch(\(q(r.url)), options);
            console.log(response.status);
            console.log(await response.text());
            """
        case .python:
            if timeout>0 {issues.append("requests timeout is a connect/read inactivity limit, not cURL's whole-operation deadline.")}
            // Do not silently approximate a requested total deadline.
            if timeout>0 {throw RequestIssue("Python requests has no whole-operation --max-time deadline. Remove --max-time or choose Swift/C#/Fetch.")}
            code="""
            # Python 3; dependency: requests 2.x
            import base64
            import requests

            session = requests.Session()
            session.trust_env = False  # do not inherit proxies or netrc credentials
            session.headers.clear()
            session.max_redirects = \(redirects)
            headers = {
            \(r.headers.map{"    \(q($0.name)): \(q($0.value)),"}.joined(separator:"\n"))
            }
            response = session.request(
                \(q(r.method)), \(q(r.url)), headers=headers,
                data=\(body.map{"base64.b64decode(\(q($0)))"} ?? "None"),
                allow_redirects=\(r.followRedirects ? "True":"False"),
                timeout=\(r.connectTimeout.map{"(\($0), None)"} ?? "None"),
            )
            print(response.status_code)
            print(response.text)
            """
        case .csharp:
            code="""
            // .NET 8+ console application
            using System;
            using System.Net;
            using System.Net.Http;
            using System.Threading.Tasks;

            using var handler = new HttpClientHandler {
                AllowAutoRedirect = \(r.followRedirects && redirects>0), MaxAutomaticRedirections = \(max(1,redirects)),
                UseCookies = false, UseProxy = false,
                AutomaticDecompression = \(r.compressed ? "DecompressionMethods.All":"DecompressionMethods.None")
            };
            using var client = new HttpClient(handler) { Timeout = \(timeout>0 ? "TimeSpan.FromSeconds(\(timeout))":"System.Threading.Timeout.InfiniteTimeSpan") };
            using var request = new HttpRequestMessage(new HttpMethod(\(q(r.method))), \(q(r.url)));
            \(body.map{"request.Content = new ByteArrayContent(Convert.FromBase64String(\(q($0))));"} ?? "")
            \(r.headers.map{h in
                if h.name.lowercased().hasPrefix("content-"){return "request.Content ??= new ByteArrayContent(Array.Empty<byte>());\nrequest.Content.Headers.TryAddWithoutValidation(\(q(h.name)), \(q(h.value)));"}
                return "request.Headers.TryAddWithoutValidation(\(q(h.name)), \(q(h.value)));"
            }.joined(separator:"\n"))
            using var response = await client.SendAsync(request);
            Console.WriteLine((int)response.StatusCode);
            Console.WriteLine(await response.Content.ReadAsStringAsync());
            """
        case .java:
            if r.compressed{throw RequestIssue("Java HttpClient does not transparently implement cURL --compressed negotiation. Choose another target.")}
            let restricted=Set(["connection","content-length","expect","host","upgrade"])
            if r.headers.contains(where:{restricted.contains($0.name.lowercased())}){throw RequestIssue("Java HttpClient restricts one of these headers. No header was silently dropped.")}
            code="""
            // JDK 17+; save as GeneratedRequest.java
            import java.net.URI;
            import java.net.http.*;
            import java.time.Duration;
            import java.util.Base64;

            public class GeneratedRequest {
                public static void main(String[] args) throws Exception {
                    var client = HttpClient.newBuilder()
                        .followRedirects(HttpClient.Redirect.\(r.followRedirects ? "NORMAL":"NEVER"))
                        \(r.connectTimeout.map{".connectTimeout(Duration.ofMillis(\(Int($0*1000))))"} ?? "")
                        .build();
                    var builder = HttpRequest.newBuilder(URI.create(\(q(r.url))))
                        \(timeout>0 ? ".timeout(Duration.ofMillis(\(Int(timeout*1000))))" : "")
                        .method(\(q(r.method)), \(body.map{"HttpRequest.BodyPublishers.ofByteArray(Base64.getDecoder().decode(\(q($0))))"} ?? "HttpRequest.BodyPublishers.noBody()"));
                    \(r.headers.map{"builder.header(\(q($0.name)), \(q($0.value)));"}.joined(separator:"\n        "))
                    var response = client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
                    System.out.println(response.statusCode());
                    System.out.println(response.body());
                }
            }
            """
        case .kotlin:
            if ["GET","HEAD"].contains(r.method.uppercased()) && body != nil {throw RequestIssue("OkHttp forbids a body with GET/HEAD. Choose a different target.")}
            code="""
            // Kotlin/JVM; dependency: com.squareup.okhttp3:okhttp:4.12.0
            import okhttp3.OkHttpClient
            import okhttp3.Request
            import okhttp3.RequestBody.Companion.toRequestBody
            import java.util.Base64
            import java.util.concurrent.TimeUnit
            import java.net.Proxy

            fun main() {
                val client = OkHttpClient.Builder()
                    .proxy(Proxy.NO_PROXY)
                    .followRedirects(\(r.followRedirects))
                    .followSslRedirects(\(r.followRedirects))
                    .callTimeout(\(Int(timeout*1000)), TimeUnit.MILLISECONDS)
                    .connectTimeout(\(Int((r.connectTimeout ?? 0)*1000)), TimeUnit.MILLISECONDS)
                    .readTimeout(0, TimeUnit.MILLISECONDS)
                    .writeTimeout(0, TimeUnit.MILLISECONDS)
                    .build()
                val body = \(body.map{"Base64.getDecoder().decode(\(q($0))).toRequestBody(null)"} ?? (["POST","PUT","PATCH","PROPPATCH","REPORT"].contains(r.method.uppercased()) ? "ByteArray(0).toRequestBody(null)":"null"))
                val request = Request.Builder().url(\(q(r.url)))
                    .method(\(q(r.method)), body)
                    \(r.headers.map{".addHeader(\(q($0.name)), \(q($0.value)))"}.joined(separator:"\n        "))
                    .build()
                client.newCall(request).execute().use { response ->
                    println(response.code)
                    println(response.body?.string())
                }
            }
            """
        }
        issues.append("Client libraries may normalize URL/header transport. Body is encoded as exact UTF-8 bytes, not reformatted JSON.")
        if r.compressed && language != .csharp && language != .java{issues.append("Selected client handles response decompression using its supported encodings.")}
        guard code.utf8.count<=4*1024*1024 else{throw RequestIssue("Resource limit: generated code exceeds 4 MiB.")}
        return GeneratedRequest(code:preamble+code+"\n",issues:issues,needsValues:needs)
    }
    private static func multipart(_ request:inout HTTPRequestSpec)throws {
        var boundary="----DeveloperToolboxBoundary"
        while request.parts.contains(where:{$0.value.contains(boundary)}){boundary+="X"}
        func field(_ s:String)throws->String {guard !s.contains("\r"),!s.contains("\n") else{throw RequestIssue("Multipart names cannot contain line breaks.")};return s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")}
        var body=""
        for part in request.parts {
            try Task.checkCancellation();body+="--\(boundary)\r\nContent-Disposition: form-data; name=\"\(try field(part.name))\""
            if let filename=part.filename{body+="; filename=\"\(try field(filename))\""}
            else if part.file {body+="; filename=\"REPLACE_WITH_FILENAME\""}
            body+="\r\n"
            if let type=part.contentType {guard !type.contains("\r"),!type.contains("\n") else{throw RequestIssue("Invalid multipart content type.")};body+="Content-Type: \(type)\r\n"}
            body+="\r\n\(part.value)\r\n"
        }
        body+="--\(boundary)--\r\n";request.body=body
        guard !request.headers.contains(where:{$0.name.lowercased()=="content-type"}) else{throw RequestIssue("Explicit multipart Content-Type conflicts with the generated boundary.")}
        request.headers.append(RequestHeader(name:"Content-Type",value:"multipart/form-data; boundary=\(boundary)",removed:false))
    }
    public static func literal(_ s:String,language:RequestLanguage)->String {
        var out="\""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 34:out+="\\\""
            case 92:out+="\\\\"
            case 10:out+="\\n"
            case 13:out+="\\r"
            case 9:out+="\\t"
            case 36 where language == .kotlin:out+="\\$"
            case 0...31,127,0x2028,0x2029:
                if language == .swift{out+="\\u{\(String(scalar.value,radix:16))}"}
                else{out+=String(format:"\\u%04X",scalar.value)}
            default:out.unicodeScalars.append(scalar)
            }
        }
        return out+"\""
    }
}
