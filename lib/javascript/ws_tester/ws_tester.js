var usbr = window.usbr || {};

usbr.ws_tester = (function($, undefined) {
    // *** Private
    var test_info = [];
    
    var html_encode = function html_encode(value) {
        //create a in-memory div, set it's inner text(which jQuery automatically encodes)
        //then grab the encoded contents back out.  The div never exists on the page.
        return $('<div/>').text(value).html();
    };    
        
    var debug = true;
    
    var request_available_tests = function request_available_tests() {
        return $.ajax({
            type:        'GET',
            url:         'data.pl',
            dataType:    'json',
            cache:        false,
            data:        {action: 'request_test_info'}
        });
    };
        
    // *** Public
    return {
        tests_to_run:                0,        
        result_file_path:            '',
        document_root:               '',
        result_info:                 new Array(),
	display_html_as_image:	     false,

        initialize:   function initialize() {
		$.pnotify.defaults.styling = 'jqueryui';

		// Create menu items.
		$('.menu').menu();

		// Create tabs.
		$('#tabs').tabs({
		    activate: function( event, ui ) {
			// Do this when a new tab is chosen
			usbr.ws_tester.display_application_names();
			usbr.ws_tester.display_test_types().done(function() {
			    var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
			    if (selected_tab == 'Review')
				usbr.ws_tester.display_run_dates();
			});
		    }       
		});
            
            request_available_tests()
                .done(function(response) {
                    if (response.status == 'success') {
                        test_info = $.map(response.tests, function(value, index) {
                            return [value];
                        });

                        usbr.ws_tester.result_info = $.map(response.results, function(value, index) {
                            return [value];
                        });

                        usbr.ws_tester.document_root = response.document_root;
                                        
                        usbr.ws_tester.display_application_names();
                        usbr.ws_tester.display_test_types().done(function() {
                            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
                            if (selected_tab == 'Review')
                                usbr.ws_tester.display_run_dates();
                        });
                    }
                    else {
                        $.pnotify({
                            title: 'Error',
                            text: response.message,
                            type: 'error'
                        });
                    }
                });
        },
            
        execute_tests:                function execute_tests() {            
            return $.ajax({
                type:        'GET',
                url:        'data.pl',
                dataType:    'json',
                cache:        false,
                data:        {action: 'execute_tests', 
                              application: $('#test_applications option:selected').val(), 
                              test_type: $('#test_test_types option:selected').val()}
            });
        },
        
        request_results:            function request_results() {
            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
            var selected_application = (selected_tab == 'Test' 
                                        ?  $('#test_applications option:selected').val() 
                                        :  $('#review_applications option:selected').val());
            var selected_test_type = (selected_tab == 'Test' 
                                      ? $('#test_test_types option:selected').val() 
                                      : $('#review_test_types option:selected').val());

            if (selected_tab == 'Review') {
                var selected_test_epoch = $('#run_dates option:selected').val();
                usbr.ws_tester.result_file_path 
                  = usbr.ws_tester.result_file_path 
                  = usbr.ws_tester.document_root 
                    + '/results/' 
                    + selected_application 
                    + '.' + selected_test_type 
                    + '.' + selected_test_epoch 
                    + '.result'
            }

            return $.ajax({
                type:        'GET',
                url:         'data.pl',
                dataType:    'json',
                cache:       false,
                data:        {action: 'request_results', 
			      application: selected_application, 
			      test_type: selected_test_type, 
			      result_file_path: usbr.ws_tester.result_file_path}
            });
        },
        
        display_application_names:    function display_application_names(response) {
            var html = '';
            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
            
            if (test_info && test_info.length > 0) {        
                // Remove all the existing options from the applications select element.
                if (selected_tab == 'Test')
                    $('#test_applications').empty();
                else if (selected_tab == 'Review')
                    $('#review_applications').empty();
                
                // Add all the application names.
                for (var i = 0, length = test_info.length; i < length; i++) {
                    html += '<option value="' + test_info[i].application + '">' + test_info[i].application + '</option>';
                }
                
                // Append the newly-created html, sort the options alphabetically.
                if (selected_tab == 'Test')
                    $('#test_applications')
                        .append(html)
                        .sortOptions();
                else if (selected_tab == 'Review')
                    $('#review_applications')
                        .append(html)
                        .sortOptions();
            }
            else {
                $.pnotify({
                    title: 'Error',
                    text: response.message,
                    type: 'error'
                });
            }

        },

        display_test_types:            function display_test_types() {
            var html = '';
            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
            var deferred = $.Deferred();
            
            if (test_info && test_info.length > 0) {
                // Remove all the existing options from the test_types select element.
                if (selected_tab == 'Test')
                    $('#test_test_types').empty();
                else if (selected_tab == 'Review')
                    $('#review_test_types').empty();
                
                var chosen_application = (selected_tab == 'Test' ? $('#test_applications option:selected').val() :  $('#review_applications option:selected').val());

                for (var i = 0, length = test_info.length; i <  length; i++) {
                    if (test_info[i].application == chosen_application) {
                        html += '<option application_type="' + test_info[i].application_type + '" value="' + test_info[i].test_type + '">' + test_info[i].test_type + '</option>';
                    }
                }
                
                // Append the newly-created html, sort the options alphabetically.
                if (selected_tab == 'Test')
                    $('#test_test_types')
                        .append(html)
                        .sortOptions();
                else if (selected_tab == 'Review')
                    $('#review_test_types')
                        .append(html)
                        .sortOptions();
            }

            deferred.resolve();

            return deferred.promise();
        },

        display_run_dates:       function display_run_dates() {
            var html = '';
            var value, date, date_wrapper, text;
            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
            var data = [];
            var member;

            if (selected_tab == 'Review' && usbr.ws_tester.result_info && usbr.ws_tester.result_info.length > 0) {
                // Remove all the existing options from the test_types select element.
                $('#run_dates').empty();

                var chosen_application = (selected_tab == 'Test' 
                                          ? $('#test_applications option:selected').val() 
                                          :  $('#review_applications option:selected').val());

                for (var i = 0, length = usbr.ws_tester.result_info.length; i <  length; i++) {
                    if (usbr.ws_tester.result_info[i].application == chosen_application) {
                        value = usbr.ws_tester.result_info[i].epoch;
                        date = new Date(value*1000);
                        date_wrapper = moment(date);
                        text = date_wrapper.format('MMM DD YYYY HH:mm:ss');
                        member = {value: value, text: text};
                        data.push(member);
                    }
                }

                data.sort(function(a,b){
                    return (b.value - a.value);
                });

                for (var i = 0, length = data.length; i < length; i++) {
                    html += '<option value="' + data[i].value + '">' + data[i].text + '</option>';
                }

                // Append the newly-created html, sort the options alphabetically.
                $('#run_dates')
                    .append(html);
            }
        },
        
        display_results:            function display_results(response) {
            // The html which will hold the table data.
            var html = '';
            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
            var container_name = (selected_tab == 'Test' 
                                  ? 'test_results_container' 
                                  : 'review_results_container');
            var application_type = (selected_tab == 'Test' 
                                    ? $('#test_test_types option:selected').attr('application_type') 
				    : $('#review_test_types option:selected').attr('application_type'));
            var iframe_content = [];

            $('#' + container_name).empty();
            
            if (response.status == 'success') {        
                if (response.data.length > 0) {
                    var response_columns = ['Metric', 'Expected', 'Comparison Method', 'Actual', 'Comparison Result'];
                                        
                    var data = $.map(response.data, function(value, index) {
                        return [value];
                    });

                    html += '<div id="accordion">';

                    for (var i = 0, length1 = data.length; i < length1; i++) {

                        html += '<h3>' + data[i].title + '</h3>';
                        html += '<div>';

                        for (var j = 0, length2 = data[i].steps.length; j < length2; j++) {

                            // Response
                            html += '<table id="table_test_' + (i + 1) + '_response_' + (j + 1) + '">';

                            if (application_type == 'web_site') {
                                if (data[i].steps[j].request.variety == 'uri') {
                                    html += '<caption>Step #' + (j+1) + ' : ' + data[i].steps[j].request.method_name.toUpperCase() + ' to ' + html_encode(data[i].steps[j].request.uri) + '</caption>';
                                }
                                else if (data[i].steps[j].request.variety == 'form') {
                                     html += '<caption>Step #' + (j+1) + ' : Form ' + data[i].steps[j].request[data[i].steps[j].request.locator] + '</caption>';
                                }
                                else {
                                     html += '<caption>Step #' + (j+1) + '</caption>';
                                }
                            }
                            else {
                                html += '<caption>Test #' + (i+1) + ' : ' + data[i].steps[j].request.method_name.toUpperCase() + ' to ' + html_encode(data[i].steps[j].request.uri) + '</caption>';
                            }
                            html += '<thead><tr>';
                        
                            for (var k = 0, length3 = response_columns.length; k < length3; k++) {
                                html += '<th>' + response_columns[k] + '</th>';
                            }
                        
                            html += '</tr></thead><tbody>';

                            if (application_type != 'web_site') {
                                // Put the response in with the metric name "response"--format as necessary.
                                html += '<tr><td>response</td>';
                                var response = data[i].steps[j].actual.content;
                                var format =  data[i].steps[j].actual.format;
                                if (format.indexOf('json') > -1) {
                                    response = vkbeautify.json(response);
                                }
                                else if (format.indexOf('xml') > -1) {
                                    response = vkbeautify.xml(response);
                                }

                                html += '<td>&nbsp;</td><td>&nbsp;</td><td><pre>' + html_encode(response) + '</pre></td><td>&nbsp;</td></tr>';
                            }
                        
                            for (var key in data[i].steps[j].expected) {
                                for (var k = 0, length3 = data[i].steps[j].expected[key].length; k < length3; k++) {
                                    html += '<tr><td>' + key + '</td>';
                                    for (var m = 0, length4 = response_columns.length; m < length4; m++) {
                                        var variety = data[i].steps[j].expected[key][k].variety;

                                        if (response_columns[m] == 'Expected') {
                                            if (key == 'headers') {
                                                html += '<td>' + html_encode(data[i].steps[j].expected[key][k].name) + ' : ' + html_encode(data[i].steps[j].expected[key][k].value) + '</td>';
                                            }
                                            else if (variety == 'logical') {
                                                html += '<td>' + html_encode(data[i].steps[j].expected[key][k].operator) + ' ' + html_encode(data[i].steps[j].expected[key][k].value) + '</td>';
                                            }
                                            else if (variety == 'xpath' || variety == 'jsonpath') {
                                                html += '<td>' + html_encode(data[i].steps[j].expected[key][k].expression) + ' : ' + html_encode(data[i].steps[j].expected[key][k].value) + '</td>';
                                            }
                                            else if (variety == 'image') {
                                                var split_result = data[i].steps[j].expected[key][k].value.split("=");
                                                html += '<td>' + html_encode(split_result[0]) + ' : ' + html_encode(split_result[1]) + '</td>';
                                            }
                                            else if (variety == 'link') {
                                                var split_result = data[i].steps[j].expected[key][k].value.split("=");
                                                html += '<td>' + html_encode(split_result[0]) + ' : ' + html_encode(split_result[1]) + '</td>';
                                            }
                                            else if (variety == 'regexp') {
                                                html += '<td>' + html_encode(data[i].steps[j].expected[key][k].value) + '</td>';
                                            }
                                        }
                                        else if (response_columns[m] == 'Comparison Method') {
                                            html += '<td>' + html_encode(variety) + '</td>';
                                        }
                                        else if (response_columns[m] == 'Actual') {
                                            var format;
                                            if (data[i].steps[j].comparison.format[k].display.indexOf('html') > -1) {
                                                format = 'html';
                                            }
                                            else if (data[i].steps[j].comparison.format[k].display.indexOf('json') > -1) {
                                                format = 'json';
                                            }
                                            else if (data[i].steps[j].comparison.format[k].display.indexOf('xml') > -1) {
                                                format = 'xml';
                                            }

                                            var display_actual_value;
                                            if (key != 'content' || data[i].steps[j].expected[key][k].variety != 'regexp') {
                                                display_actual_value = html_encode(data[i].steps[j].comparison[key][k].display);
                                            }
                                            else {
                                                if (format == 'html') {
                                                    if (usbr.ws_tester.display_html_as_image == true) {
                                                        // Push the content onto the iframe_content[] array.  We'll add this content to the iframe document later.
                                                        iframe_content.push(data[i].steps[j].comparison[key][k].display);
                                                        display_actual_value = '<iframe id="response_body_' + iframe_content.length + '" class="response_body"></iframe>';
                                                    }
                                                    else {
                                                        // If we're going to display html, remove everything between the <head></head> tags.
                                                        var regx = /\<head\>.+\<\/head\>/i;
                                                        var new_content = html_beautify(data[i].steps[j].comparison[key][k].display.replace(regx, "<head></head>"));
                                                        display_actual_value = '<pre>' + html_encode(new_content) + '</pre>';
                                                    }
                                                }
                                                else if (format == 'json') {
                                                    display_actual_value = '<pre>' + html_encode(vkbeautify.json(data[i].steps[j].comparison[key][k].display)) + '</pre>';
                                                }
                                                else if (format == 'xml') {
                                                    display_actual_value = '<pre>' + html_encode(vkbeautify.xml(data[i].steps[j].comparison[key][k].display)) + '</pre>';
                                                }
                                                else {
                                                    display_actual_value = html_encode(data[i].steps[j].comparison[key][k].display);
                                                }
                                            }
                                            html += '<td>' + display_actual_value + '</td>';
                                        }
                                        else if (response_columns[m] == 'Comparison Result') {
                                            var status = data[i].steps[j].comparison[key][k].status;
                                            var color = (status === 'PASS' ? 'green' : 'red');
                                            html += '<td style="background-color:' + color + '">' + status + '</td>';
                                        }
                                    }
                                }
                                html += '</tr>';
                            }
                        }
                        html += '</tbody></table>';
                        html += '</div>';
                    }

                    html += '</div>'

                    $('#' + container_name).append(html);

                    $('table').tablesorter({
                        widgets : ['zebra', 'response_columns']
                    });

                    if (usbr.ws_tester.display_html_as_image == true) {
                        // Iterate through each of the iframes.  We're going to put an image of the HTML content inside.
                        var iframes = $('iframe').each( function() {
                            // This iframe.
                            var iframe = this;

                            // This iframe's document object.
                            var iframe_doc = iframe.contentDocument || iframe.contentWindow.document;

                            // The index of the html content that we will put into the iframe.
                            var indx = $(iframe).attr('id').split('response_body_')[1] - 1;

                            // Put the html content into the iframe document.
                            $('body', $(iframe_doc)).html(iframe_content[indx]);

                            // Here's where the magic happens!
                            html2canvas(iframe_doc.body, {
                                onrendered: function(canvas) {
                                    $('body', $(document)).append(canvas);
                                    $('body', $(document)).remove(iframe);
                                }
                            });
                        });
                    }

                    $( "#accordion" ).accordion({
                        collapsible: true,
                        active: false
                    });
                }
            }
            else {
                $.pnotify({
                    title: 'Error',
                    text: response.message,
                    type: 'error'
                });
            }        
        }
    };
    
})(jQuery);

jQuery(document)
.ajaxSend(function( event, jqxhr, settings ) {
    $('#test_wait').spin();
    $('#review_wait').spin();
})
.ajaxStop(function( event, jqxhr, settings ) {
    $('#test_wait').spin(false);
    $('#review_wait').spin(false);
})
.ready( function() {
    usbr.ws_tester.initialize();
        
    // Do this if someone presses the #execute button.
    $('#execute').on('click', function(event) {
        $('#test_results_container').empty();

        // Start the text executions.
        usbr.ws_tester.execute_tests()
            .done(function(response) {
                if (response.status == 'success') {
                    // The path to the results file.
                    usbr.ws_tester.result_file_path = response.data.result_file_path;

                    usbr.ws_tester.request_results()
                        .done(usbr.ws_tester.display_results);

                    // Push this onto the result_info[] array so that it can be accessed from the Review tab.
                    var file_name = response.data.result_file_path.split('/').reverse()[0];
                    var file_parts = file_name.split('.');
                    var application = file_parts[0];
                    var test_type = file_parts[1];
                    var epoch = file_parts[2];

                    usbr.ws_tester.result_info.push({
			application: application, 
			path: response.data.result_file_path, 
			test_type: test_type, 
			epoch: epoch});
                }
                else {
                    $.pnotify({
                        title: 'Error',
                        text: response.message,
                        type: 'error'
                    });
                }
            });
    });

    // Do this if someone presses the #get button.
    $('#get').on('click', function(event) {
        $('#review_results_container').empty();

        usbr.ws_tester.request_results()
            .done(usbr.ws_tester.display_results);
    });

    // Do this if someone selects a new Application value from the Test tab.
    $('#test_applications').on('change', function (event) {
        $('#test_results_container').empty();
        usbr.ws_tester.display_test_types();
    });

    // Do this if someone selects a new Application value from the Review tab.
    $('#review_applications').on('change', function (event) {
        usbr.ws_tester.display_test_types().done(function() {
            var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
            $('#review_results_container').empty();

            if (selected_tab == 'Review')
                usbr.ws_tester.display_run_dates();
        });
    });

    // Do this if someone selects a new Test Types value from the Review tab.
    $('#review_applications').on('change', function(event) {
        var selected_tab = $("#tabs ul.ui-tabs-nav li.ui-state-active a").text();
        var container_name = (selected_tab == 'Test' ? 'test_results_container' : 'review_results_container');
        $('#' + container_name).empty();
        usbr.ws_tester.display_run_dates();
    });
});
