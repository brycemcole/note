var NotesAppShareExtension = function() {};

NotesAppShareExtension.prototype = {
    run: function(arguments) {
        // Get the current page URL and title
        var url = document.URL;
        var title = document.title;
        var selectedText = "";
        
        // Try to get selected text if any
        if (window.getSelection) {
            selectedText = window.getSelection().toString();
        }
        
        // If no selection, try to get page description
        var description = "";
        var metaDescription = document.querySelector('meta[name="description"]');
        if (metaDescription) {
            description = metaDescription.getAttribute('content');
        }
        
        // Return the extracted data
        arguments.completionFunction({
            "URL": url,
            "title": title,
            "selectedText": selectedText,
            "description": description
        });
    },
    
    finalize: function(arguments) {
        // Return data for the extension to use
        return {
            "URL": arguments["URL"],
            "title": arguments["title"],
            "selectedText": arguments["selectedText"],
            "description": arguments["description"]
        };
    }
};

var ExtensionPreprocessingJS = new NotesAppShareExtension;