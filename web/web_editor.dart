import 'dart:json';
import 'package:pwt_proto/pwt_proto.dart';

final String SERVER_URL = ''; //'http://127.0.0.1:8080/';

void main() {
  new WebEditor();
}

class WebEditor {
  WebEditorView view;
  
  Element lastError;
  
  Mask mask;
  
  WebEditor() {
    // Get <body>
    var body = query('body');
    
    view = new WebEditorView();
    view.addTo(body, 'afterBegin');
    
    bind(view);
  }
  
  void bind(WebEditorView view) {
    view.linedTextarea.textarea.onKeyDown.listen(keyHandler);

    // The lined textarea is now inside the DOM => we can generate the lines
    view.linedTextarea.onScroll(null);
    
    // Listen to the run button
    view.runButton.onClick.listen(runProgram);
  }

  void runProgram(e) {
    // Add Mask
    mask = new Mask()
      ..add()
      ..style.backgroundColor = '#ffd';
    
    // Get environment & source code
    final String envName = view.listboxEnv.selectedOptions[0].value;
    final String sourceCode = view.linedTextarea.textarea.value;

    // Send it to the server
    var url = "${SERVER_URL}compile?env=$envName";
    final HttpRequest request = new HttpRequest();
    request.open("POST", url);
    request.setRequestHeader('Content-Type', 'text/plain');
    //request.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    //request.withCredentials = true;
    
    
    request.onReadyStateChange.listen((_) {
      if (request.readyState == HttpRequest.DONE) {
        if (lastError != null) {
          lastError.classes.remove('lineerror');
        }
        
        if (request.status == 200 || request.status == 0) {
          if (envName == 'server') {
            view.output.innerHtml = '<pre class="error">${request.responseText}</pre>';
            mask.remove();
          } else {
            view.output.innerHtml = '';
            requestJavascript(request.responseText);
          }
        } else {
          if (request.status == 503) {
            view.output.innerHtml = '<pre class="error">Importing "dart:io" is forbidden</pre>';
          } else {
            String json = request.responseText;
            Map jsonObj = parse(json);
            
            if (jsonObj['lineError'] != null) {
              lastError = view.linedTextarea.linesDiv.children[jsonObj['lineError'] - 1];
              lastError.classes.add('lineerror');
            }
            
            view.output.innerHtml = '<pre class="error">${jsonObj['msg']}</pre>';
          }
          
          mask.remove();
        }
      }
    });
    
    request.send(sourceCode);
  }

  void requestJavascript(String fileName) {
    //print(fileName);
    var url = "${SERVER_URL}html?file=$fileName";
    
    final Element iframe = new Element.html('<iframe seamless src="$url" width="90%" height="100%" style="margin:auto">');

    mask
      ..onClick((Event _) => mask.remove())  
      ..append(iframe)
      ..opacity = 1;
  }

  void keyHandler(KeyboardEvent e) {
    if(e.keyCode == KeyCode.TAB) {
      var textarea = e.target;
      int startIndex = textarea.selectionStart;
      int endIndex = textarea.selectionEnd;
      
      String currentValue = textarea.value;
      textarea.value = '${currentValue.substring(0, startIndex)}  ${currentValue.substring(endIndex)}';
      textarea.selectionStart = textarea.selectionEnd = startIndex + 2;

      e.preventDefault();
    }
  }
}

class WebEditorView {
  var htmlBuilder;
  var listboxEnv;
  var runButton;
  var linedTextarea;
  var output;
  
  WebEditorView() {
    // Build a lined <textarea>
    linedTextarea = new LinedTextarea();
    linedTextarea.textarea
      ..id = 'code'
      ..name = 'code'
      ..attributes['autocorrect'] = 'off'
      ..attributes['autocomplete'] = 'off'
      ..attributes['autocapitalize'] = 'off'
      ..attributes['spellcheck'] = 'false';
    
    // Output
    output = element('div', {'id':'output'}, '');
    
    // Build a drop down list
    var envBuilder = builder()
      ..select({'id':'env', 'name':'env'})
        ..option({'value':'client'}, 'Client')
        ..option({'value':'server'}, 'Server')
      ..end();
    listboxEnv = envBuilder.content[0];
    
    // Build a Run button
    runButton = element('input', {'type':'button', 'value':'Run', 'id':'run'});
    
    // Build the layout
    htmlBuilder = builder()
      ..div({'id' : 'banner'})
        ..div({'id' : 'head'}, 'Dart Playground')
        ..div({'id' : 'controls'})
          ..span(null, 'Environment: ')
          ..addElement(listboxEnv)
          ..addElement(runButton)
        ..end()
      ..end()
      ..div({'id':'wrap'})
        ..addElement(e(linedTextarea.element))
      ..end()    
      ..addElement(output);
  }
  
  void addTo(Element parent, [String where = 'afterEnd']) {
    htmlBuilder.addTo(parent, where);
  }
}