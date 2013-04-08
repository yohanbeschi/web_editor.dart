import 'dart:io';
import 'dart:async';

final String SERVER_URL = '127.0.0.1';
final int SERVER_PORT = 8080;
final String OUTPUT_DIRECTORY = 'C:/Users/soat/Downloads/dart/';
final String DART = 'C:/Programming/softs/darteditor-win32-64.20810/dart/dart-sdk/bin/dart.exe';
final String DART_TO_JS = 'C:/Programming/softs/darteditor-win32-64.20810/dart/dart-sdk/bin/dart2js.bat';

main() {
  HttpServer.bind(SERVER_URL, SERVER_PORT).then(addRequestListener);
  print("Listening...");
}

Future addRequestListener(HttpServer server) {
  server.listen(onRequest);
}

void onRequest(HttpRequest request) {
  switch (request.method) {
    case "OPTIONS": 
      handleOptions(request);
      break;
    default: defaultHandler(request);
  }
}

void handleOptions(HttpRequest req) {
  final HttpResponse res = req.response;
  addCorsHeaders(res);
  res.statusCode = HttpStatus.NO_CONTENT;
  res.close();
}

void defaultHandler(HttpRequest request) {
  //print(request.uri.path);
  
  // Compile
  if (request.uri.path == '/compile') {
    _processSource(request);
  }
  
  // Get html file
  else if (request.uri.path == '/html') {
    _getHtml(request);
  }
  
  // Get compiled file
  else if (request.uri.path == '/prog') {
    String fileName = request.queryParameters['file'];
    final String path = '$OUTPUT_DIRECTORY$fileName';
    _serveFile(request, path, 'application/javascript');
  }
  
  // Html, CSS, Dart, JS
  else if (request.uri.path == '/' || request.uri.path == '/web_editor.html') {
    _serveFile(request, 'web/web_editor.html', 'text/html');
  } else if (request.uri.path == '/web_editor.css') {
    _serveFile(request, 'web/web_editor.css', 'text/css');
  } else if (request.uri.path == '/web_editor.dart') {
    _serveFile(request, 'web/web_editor.dart', 'application/dart');
  } else if (request.uri.path == '/web_editor.dart.js') {
    _serveFile(request, 'web/web_editor.dart.js', 'application/javascript');
  } else if (request.uri.path.contains('dart.js')) {
    _serveFile(request, 'packages/browser/dart.js', 'application/javascript');
  } else if (request.uri.path.startsWith('/packages')) {
    _serveFile(request, request.uri.path.replaceFirst('/', ''), 'application/dart');
  }
  
  // Unknown
  else {
    _pageNotFound(request.response);
  }
}

void _pageNotFound(HttpResponse response) {
  addCorsHeaders(response);
  response.statusCode = HttpStatus.NOT_FOUND;
  response.close();
}

void addCorsHeaders(HttpResponse res) {
  res.headers.add("Access-Control-Allow-Origin", "*, "); //http://127.0.0.1:3030
  res.headers.add("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.headers.add("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
  res.headers.add("Access-Control-Allow-Credentials", "true");
}

void _processSource(HttpRequest request) {
  final String env = request.queryParameters['env'];
  
  if (env == 'client') {
    _processClientCode(request);
  } else if (env == 'server') {
    _processServerCode(request);
  } else {
    _pageNotFound(request.response);
  }
}

void _serveFile(HttpRequest request, String path, String contentType) {
  final File file = new File(path);
  
  if(file.existsSync()) {
    request.response.headers.add(HttpHeaders.CONTENT_TYPE, contentType);
    file.readAsBytes().asStream().pipe(request.response); // automatically close output stream
  } else {
    _pageNotFound(request.response);
  }
}

void _getHtml(request) {
  String uid = request.queryParameters['file'];
  
  // Build html file with js file
  String html = 
'''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Web editor</title>
    <style>
      /*html{width:100%; height:100%}*/
      body{background-color:#fff;}
    </style>
  </head>
  <body>

    <script src="http://$SERVER_URL:$SERVER_PORT/prog?file=$uid.dart.js"></script>
  </body>
</html>
''';
  
  request.response.headers.contentType = new ContentType.fromString('text/html');
  request.response.statusCode = HttpStatus.OK;
  request.response.write(html);
  request.response.close();
}

void _processServerCode(HttpRequest request) {
  request.listen(processServerData(request), onError: printError);
}

Function processServerData(HttpRequest request) =>
  (List<int> buffer) {
    final String uid = getNewId();
    final String path = '$OUTPUT_DIRECTORY$uid.dart';
    final File file = new File(path);

    if (isIoImportPresents(buffer)) {
      request.response.statusCode = HttpStatus.FORBIDDEN;
      addCorsHeaders(request.response);
      request.response.close();
    } else {
      var ioSink = file.openWrite(); // save the data to the file
      for (int charCode in buffer) {
        ioSink.writeCharCode(charCode);
      }
      ioSink.close();
      
      //Async
      executeProgram(request, uid, DART, [path], (response, result) => response.write(result));
    }
  };

String getNewId() {
  bool newFileGenerated = false;
  while (true) {
    // Get uid
    final String uid = new DateTime.now().millisecondsSinceEpoch.toString();
    final File file = new File('$OUTPUT_DIRECTORY$uid.dart');
    
    final bool exists = file.existsSync();
    if (!exists) {
      return uid;
    }
  }
}

bool isIoImportPresents(List<int> buffer) {
  // 100 97 114 116 58 105 111 
  final List io = [100, 97, 114, 116, 58, 105, 111];
  int currentIoIndex = 0;
  final Iterator it = buffer.iterator;
  while (it.moveNext()) {
    //print();
    
    if (io[currentIoIndex] == it.current) {
      currentIoIndex++;
    } else {
      currentIoIndex = 0;
      
      if (io[currentIoIndex] == it.current) {
        currentIoIndex++;
      }
    }
    
    if (currentIoIndex == io.length) {
      return true;
    }
  }
  
  return false;
}

String executeProgram(HttpRequest request, String fileName, String program, List<String> args, Function dealWithServerExecution) {
  Process.run(program, args).then((result) {
    addCorsHeaders(request.response);

    if ((program == DART && result.exitCode != 0) || (program == DART_TO_JS && result.stdout != '')) {
      String errors = program == DART ? result.stderr : result.stdout;
      processCompilationErrors(request, errors, fileName);
    } else {
      request.response.statusCode = HttpStatus.OK;
      request.response.headers.contentType = new ContentType.fromString('text/plain');
      dealWithServerExecution(request.response, result.stdout);
    }

    request.response.close();
  });
}

void processCompilationErrors(HttpRequest request, String errors, String fileName) {
  request.response.statusCode = HttpStatus.BAD_REQUEST;

  int index = errors.indexOf(fileName);
  index +=  fileName.length + 6; //.dart:
  StringBuffer line = new StringBuffer();
  for (int i = index; i < errors.length; i++) {
    final curChar = errors[i];
    if (curChar != ':') {
      line.write(curChar);
    } else {
      break;
    }
  }
  
  
  errors = errors.replaceAll(OUTPUT_DIRECTORY, '');
  errors = errors.replaceAll(fileName, 'prog');
  errors = errors.replaceAll('file:', '');
  errors = errors.replaceAll('/', '');
  errors = errors.replaceAll('\n', '\\n');
  errors = errors.replaceAll('\r', '\\r');
  errors = errors.replaceAll('\r\n', '\\r\\n');
  request.response.headers.contentType = new ContentType.fromString('application/json');
  request.response.write('{"lineError":${int.parse(line.toString())}, "msg":"$errors"}');
}

void _processClientCode(request) {
  request.listen(processClientData(request), onError: printError);
}

Function processClientData(HttpRequest request) =>
    (List<int> buffer) {
  final String uid = getNewId();
  final String path = '$OUTPUT_DIRECTORY$uid.dart';
  final File file = new File(path);

  var ioSink = file.openWrite(); // save the data to the file
  for (int charCode in buffer) {
    ioSink.writeCharCode(charCode);
  }
  ioSink.close();
  
  //Async
  var args = [path, '-o$path.js', '--minify'];
  executeProgram(request, uid, DART_TO_JS, args, (response, result) => response.write(uid));
};

void printError(error) => print(error);