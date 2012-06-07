
import api.Program;
import haxe.remoting.HttpAsyncConnection;
import js.codemirror.CodeMirror;
import js.JQuery;

using js.bootstrap.Button;
using Lambda;
using StringTools;

class Editor {

	var cnx : HttpAsyncConnection;
	
	var program : Program;
	var output : Output;
	
	var gateway : String;
	
	var form : JQuery;
	var haxeSource : CodeMirror;
	var jsSource : CodeMirror;
	var runner : JQuery;
	var messages : JQuery;
	var compileBtn : JQuery;
  var libs : JQuery;
  var markers : Array<MarkedText>;
  var lineHandles : Array<LineHandle>;

  var completions : Array<String>;
  var completionIndex : Int;

	public function new(){
    markers = [];
    lineHandles = [];

		CodeMirror.commands.autocomplete = autocomplete;
    CodeMirror.commands.compile = function(_) compile();

  	haxeSource = CodeMirror.fromTextArea( cast new JQuery("textarea[name='hx-source']")[0] , {
			mode : "javascript",
			theme : "rubyblue",
			lineWrapping : true,
			lineNumbers : true,
			extraKeys : {
				"Ctrl-Space" : "autocomplete",
        "Ctrl-Enter" : "compile"
			},
      onChange : onChange
		} );

   
		jsSource = CodeMirror.fromTextArea( cast new JQuery("textarea[name='js-source']")[0] , {
			mode : "javascript",
			theme : "rubyblue",
			lineWrapping : true,
			lineNumbers : true,
			readOnly : true
		} );
		
		runner = new JQuery("iframe[name='js-run']");
		messages = new JQuery(".messages");
		compileBtn = new JQuery(".compile-btn");
    libs = new JQuery("#hx-options-form .hx-libs .controls");
      
		new JQuery("body").bind("keyup", onKey );

		new JQuery("a[data-toggle='tab']").bind( "shown", function(e){
			jsSource.refresh();
		});
		
		compileBtn.bind( "click" , compile );

		gateway = new JQuery("body").data("gateway");
		cnx = HttpAsyncConnection.urlConnect(gateway);

    program = {
      uid : null,
      main : {
        name : "Test",
        source : haxeSource.getValue()
      },
      target : JS( "test" ),
      libs : new Array()
    };

    initLibs();

		var uid = js.Lib.window.location.hash;
		if (uid.length > 0){
      uid = uid.substr(1);
  		cnx.Compiler.getProgram.call([uid], onProgram);
    }
  }

  function initLibs(){
    for (l in Libs.getAvailableLibs(program.target)) // fill libs form
    {
      libs.append(
        
        '<label class="checkbox"><input class="lib" type="checkbox" value="' + l.name + '" ' 
        + ((l.checked /*|| selectedLib(l.name)*/) ? "checked='checked'" : "") 
        + '" /> ' + l.name 
        + "<span class='help-inline'><a href='http://lib.haxe.org/p/" + l.name +"' target='_blank'><i class='icon-question-sign'></i></a></span>"
        + "</label>"
        );
    }
  }

	function onProgram(p:Program)
	{
		//trace(p);
		if (p != null)
		{
			// sharing
			program = p;
			haxeSource.setValue(program.main.source);
      if( program.libs != null ){
        for( lib in libs.find("input.lib") ){
          if( program.libs.has( lib.val() ) ){
            lib.attr("checked","checked");
          }else{
            lib.removeAttr("checked");
          }
        }
      }
		}

	}

	public function autocomplete( cm : CodeMirror ){
		updateProgram();
    var src = cm.getValue();

    var idx = SourceTools.getAutocompleteIndex( src , cm.getCursor() );
    if( idx == null ) return;

    if( idx == completionIndex ){
      displayCompletions( cm , completions ); 
      return;
    }
    completionIndex = idx;
    cnx.Compiler.autocomplete.call( [ program , idx ] , function( comps ) displayCompletions( cm , comps ) );
	}

  function showHint( cm : CodeMirror ){
    var src = cm.getValue();
    var cursor = cm.getCursor();
    var from = SourceTools.indexToPos( src , SourceTools.getAutocompleteIndex( src, cursor ) );
    var to = cm.getCursor();

    var token = src.substring( SourceTools.posToIndex( src, from ) , SourceTools.posToIndex( src, to ) );

    var list = [];

    for( c in completions ){
      if( c.toLowerCase().startsWith( token.toLowerCase() ) ){
        list.push( c );
      }
    }

    return {
        list : list,
        from : from,
        to : to
    };
  }

	public function displayCompletions(cm : CodeMirror , comps : Array<String> ) {
		completions = comps;
    CodeMirror.simpleHint( cm , showHint );
	}

  public function onKey( e : JqEvent ){
   if( e.ctrlKey && e.keyCode == 13 ){ // Ctrl+Enter
     compile(e);
   }
  }

	public function onChange( cm :CodeMirror, e : js.codemirror.CodeMirror.ChangeEvent ){
    var txt :String = e.text[0];
    if( txt.trim().endsWith( ".") ){
      autocomplete( haxeSource );
    }
	}

	public function compile(?e){
		if( e != null ) e.preventDefault();
    clearErrors();
		compileBtn.buttonLoading();
		updateProgram();
		cnx.Compiler.compile.call( [program] , onCompile );
	}

	function updateProgram(){
		program.main.source = haxeSource.getValue();

		var libs = new Array();
		var inputs = new JQuery("#hx-options .hx-libs input.lib:checked");
		// TODO: change libs array only then need
		for (i in inputs)  // refill libs array, only checked libs
		{
			//var l:api.Program.Library = { name:i.attr("value"), checked:true };
			//var d = Std.string(i.data("args"));
			//if (d.length > 0) l.args = d.split("~");
			libs.push(i.val());
		}

		program.libs = libs;
	}

	public function run(){
		if( output.success ){
  		var run = gateway + "?run=" + output.uid + "&r=" + Std.string(Math.random());
  		runner.attr("src" , run );
		}else{
			runner.attr("src" , "about:blank" );
		}
	}

	public function onCompile( o : Output ){

		js.Lib.window.location.hash = "#" + o.uid;

		output = o;
		program.uid = output.uid;
		
		jsSource.setValue( output.source );
		
		if( output.success ){
			messages.html( "<div class='alert alert-success'><h4 class='alert-heading'>" + output.message + "</h4><pre>"+output.stderr+"</pre></div>" );
		}else{
			messages.html( "<div class='alert alert-error'><h4 class='alert-heading'>" + output.message + "</h4><pre>"+output.stderr+"</pre></div>" );
      markErrors();
		}

		compileBtn.buttonReset();

		run();

	}

  public function clearErrors(){
    for( m in markers ){
      m.clear();
    }
    markers = [];
    for( l in lineHandles ){
      haxeSource.clearMarker( l );
    }
  }

  public function markErrors(){
    var errLine = ~/([^:]*):([0-9]+): characters ([0-9]+)-([0-9]+) :(.*)/g;
    
    for( e in output.errors ){
      if( errLine.match( e ) ){
        var err = {
          file : errLine.matched(1),
          line : Std.parseInt(errLine.matched(2)) - 1,
          from : Std.parseInt(errLine.matched(3)),
          to : Std.parseInt(errLine.matched(4)),
          msg : errLine.matched(5)
        };
        if( StringTools.trim( err.file ) == "Test.hx" ){
          //trace(err.line);
          var l = haxeSource.setMarker( err.line , "<i class='icon-warning-sign icon-white'></i>" , "error");
          lineHandles.push( l );

          var m = haxeSource.markText( { line : err.line , ch : err.from } , { line : err.line , ch : err.to } , "error");
          markers.push( m );
        }
        
      }
    }
  }

}