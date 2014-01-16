use 5.006;
use strict;
use warnings FATAL => 'all';
use autodie;

{
    package USBR::Result::WebServiceRest;
    
    use Carp 'confess';
    use Carp::Always;

    use Data::Dumper;
    
    use File::Basename;
    use File::Spec;
    use JSON::XS;
    use JSON::Schema;
    use JSON::Path;
    use XML::LibXML;
    use XML::LibXML::XPathContext;
    use Time::HiRes qw(gettimeofday tv_interval);
    use POSIX;
        
    $| = 1;
    
    my $log_it = 0;
    my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;
    
    my $debug = 1;
    
    my @results;
    
    # Convenience methods.
    sub comparison {
        my $attribute_name = shift;
        my $value_actual = shift;
        my $actual_comparison_hash_ref = shift;
                        
        my $answer = {'status' => 'PASS'};
        
        my $variety = $actual_comparison_hash_ref->{'variety'};
        my $value_expected = $actual_comparison_hash_ref->{'value'};

        my $expression = (exists($actual_comparison_hash_ref->{'expression'}) ? $actual_comparison_hash_ref->{'expression'} : undef);
        my $operator = (exists($actual_comparison_hash_ref->{'operator'}) ? $actual_comparison_hash_ref->{'operator'} : undef);
        my $name = (exists($actual_comparison_hash_ref->{'name'}) ? $actual_comparison_hash_ref->{'name'} : undef);

        # It is possible that $value_actual is a list, hash or an HTTP::Headers object, which is itself a hash.

        if ($variety eq 'logical') {
            my $command = "$value_actual $operator $value_expected";
            my $correct = eval $command;
            if ($@) {
                my $message = "Could not determine if the response $attribute_name ($value_actual) was as expected: $@";
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
            }
            elsif (!$correct) {
                my $message = qq{The response $attribute_name value "$value_actual" is not "$operator" "$value_expected"};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
            }
        }
        elsif ($variety eq 'regexp') {
            #$value_expected = qr/$value_expected/;

            if (ref($value_actual) eq 'HTTP::Headers') {
                if (not defined($name)) {
                    confess qq{Can't compare actual to expected values of HTTP headers unless we know the name of the header that you are interested in};
                }

                my $found_header_name = 0;
                my @header_names = map { lc($_) } $value_actual->header_field_names;
                foreach my $header_name (@header_names) {
                    if (lc($name) eq $header_name) {
                        $found_header_name = 1;
                        my $value_act = $value_actual->header($header_name);
                        if ($value_act !~ m/$value_expected/) {
                            my $message = qq{The "$name" header value of "$value_act" does not match the $variety expression "$value_expected"};
                            $answer->{'status'} = 'FAIL';
                            $answer->{'message'} = $message;
                        }        
                    }
                }

                if (!$found_header_name) {
                    my $message = qq{Could not find a "$name" header};
                    $answer->{'status'} = 'FAIL';
                    $answer->{'message'} = $message;
                }
            }
            elsif (defined(ref($value_actual)) and ref($value_actual)) {
                confess qq{Comparing against an actual value of "}, ref($value_actual), qq{" objects has not yet been implemented};
            }
            elsif ($value_actual !~ m/$value_expected/) {
                my $message = qq{Got a response $attribute_name value of "$value_actual", which does not match the $variety expression "$value_expected"};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
            }
        }
        elsif ($variety eq 'jsonpath') {        
            my $jpath   = JSON::Path->new($expression);
            my @nodes   = $jpath->values($value_actual);
            my $num_nodes = (@nodes and scalar(@nodes) ? scalar(@nodes) : 0);
            if ($num_nodes != 1) {
                my $message = qq{Found $num_nodes response $attribute_name nodes matching the $variety expression "$expression":  Expected exactly one match};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
            }
            else {
                my $value_actual = $nodes[0];
                $value_actual =~ s/^\s+//;
                $value_actual =~ s/\s+$//;
                
                if ($value_actual ne $value_expected) {
                    my $message = qq{The response $attribute_name value found at $variety "$expression" is "$value_actual" instead of the expected value "$value_expected"};
                    $answer->{'status'} = 'FAIL';
                    $answer->{'message'} = $message;
                }
            }    
        }
        elsif ($variety eq 'xpath') {
            my $xml_document = shift;
            
            my $xpath_context = XML::LibXML::XPathContext->new($xml_document->documentElement());
            my @nodes = $xpath_context->findnodes($expression);
            my $num_nodes = (@nodes and scalar(@nodes) ? scalar(@nodes) : 0);
            if ($num_nodes != 1) {
                my $message = qq{Found $num_nodes response $attribute_name nodes matching the $variety expression "$expression":  Expected exactly one match};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
            }
            else {
                my $value_actual = $nodes[0]->nodeValue;
                $value_actual =~ s/^\s+//;
                $value_actual =~ s/\s+$//;
                
                if ($value_actual ne $value_expected) {
                    my $message = qq{The response $attribute_name value found at $variety "$expression" is "$value_actual" instead of the expected value "$value_expected"};
                    $answer->{'status'} = 'FAIL';
                    $answer->{'message'} = $message;
                }
            }
        }
        
        return $answer
    }

    # Object Methods
    sub new {
        my ($class, $application, $test_type, $application_specifications, $test_specification, $agent, $log_fh, $epoch_seconds) = @_;    

        my $document_root;
        if (not exists($ENV{DOCUMENT_ROOT})) {
            my ($volume, $directories, $file) = File::Spec->splitpath(File::Spec->rel2abs(__FILE__));
            my @directories = File::Spec->splitdir($directories);
            
            # Remove the the last five elements from @directories.
            splice(@directories, -5);
            
            # Put it all back together.
            if ($volume) {
                $document_root = File::Spec->catdir($volume, @directories);
            }
            else {
                $document_root = File::Spec->catdir(@directories);
            }
        }
        else {
            $document_root = $ENV{DOCUMENT_ROOT};
        }

        # Loop through each test in the specifications file.  Get the specifications (test to run) as well as the expected results.
        
        my $test_specification_directory =  File::Spec->catdir($document_root, 'specifications');
        my $test_specification_file_path = File::Spec->catfile($test_specification_directory, "$application.$test_type.specifications");
        
        # Create unblessed copy. NECESSARY ?????????????????
        $test_specification = [@$test_specification];
        
        my @result;
                
        my $test_counter = 0;
        foreach my $i (0 .. $#$test_specification) {
            $test_counter++;

            my %test;

            $test{'title'} = $test_specification->[$i]->{'title'};

            my $step_counter = 0;
            foreach my $j ( 0 .. $#{ $test_specification->[$i]->{'steps'} }) {
                $step_counter++;

                my $request = $test_specification->[$i]->{'steps'}->[$j]->{'request'};

                if ($request->{'variety'} ne 'uri') {
                    confess qq{Invalid request variety--Must be "uri", but you passed the value "$request->{'variety'}"};
                }

                if (!exists($request->{'target'}->{'uri'})) {
                    confess qq{Invalid request target--you did not specify a request target uri value};
                }

                my %step;

                $step{'request'}{'variety'} = $request->{'variety'};

                my $uri = URI->new();
                $uri->scheme($request->{'target'}->{'uri'}->{'scheme'});
                $uri->host($request->{'target'}->{'uri'}->{'host'});        
                $uri->port($request->{'target'}->{'uri'}->{'port'});        
                
                if (exists($request->{'target'}->{'uri'}->{'path'})) {
                    $uri->path($request->{'target'}->{'uri'}->{'path'});    
                }
                
                if (exists($request->{'target'}->{'uri'}->{'query'})) {
                    $uri->query_form($request->{'target'}->{'uri'}->{'query'});    
                }
                
                if (exists($request->{'target'}->{'uri'}->{'fragment'})) {
                    $uri->fragment($uri->host($request->{'target'}->{'uri'}->{'fragment'}));    
                }

                $uri = $uri->as_string;
                            
                if (exists($application_specifications->{'authorization'}) and defined($application_specifications->{'authorization'})) {
                    if ($application_specifications->{'authorization'}->{'method'} eq 'X-Authorization') {
                        $agent->default_header('X-Authorization' => $application_specifications->{'authorization'}->{'key'});
                    }
                }
            
                my $method_name = lc $request->{'target'}->{'method'};

                $step{'request'}{'method_name'} = $method_name;
                    
                # Make the HTTP call and get the response.
                my $start = [gettimeofday];
                my $response;
                eval {
                    if (!defined($test_specification->[$i]->{'request'}->{'body'})) {
                        $response = $agent->$method_name($uri);
                    }
                    else {
                        $response = $agent->$method_name($uri, 'Content' => $test_specification->[$i]->{'request'}->{'body'});
                    }
                };
                if ($@) {
                    confess qq{Test # $test_counter could not be executed: $@};
                }
                
                my %result;
                
                $result{'actual'}{'timestamp'}    = POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($start->[0]));
                
                $result{'actual'}{'time'}        = tv_interval ($start, [gettimeofday]);                            
                $result{'actual'}{'code'}         = $response->code;
                $result{'actual'}{'uri'}         = $response->base;
                $result{'actual'}{'headers'}            = $response->headers;
                $result{'actual'}{'content'}            = $response->content;
                $result{'actual'}{'format'}        = $response->header('Content-Type') || $response->content_type();
                $result{'actual'}{'size'}        = $response->header('Content-Length') || length($response->content);
                                
                # Compare the these actual results with the expected results.
                
                my $response_expected = $test_specification->[$i]->{'steps'}->[$j]->{'response_expected'};
                
                my $parser = XML::LibXML->new();
                my $xml_document;
                
                if (index($result{'actual'}{'format'}, 'xml') > -1) {
                    eval {
                        $xml_document =  XML::LibXML->load_xml(string => $response->content);
                    };
                    if ($@) {
                        confess qq{The response is not XML as expected: $@}
                    }
                }
                
                # Save the expected results for displaying later.
                foreach my $attrib_name (keys %{ $response_expected }) {
                    foreach my $thingy (@{ $response_expected->{$attrib_name} }) {
                        foreach my $thingy_attribute (keys %{ $thingy }) {
                            $result{'expected'}{$attrib_name}{$thingy_attribute} = $thingy->{$thingy_attribute};
                        }
                    }
                }
                
                my @typical_attributes = ('headers', 'time', 'format', 'code', 'format', 'content', 'size');
                
                foreach my $attribute (@typical_attributes) {                                    
                    if (defined($response_expected->{$attribute})) { 
                        foreach my $k ( 0 .. $#{ $response_expected->{$attribute} }) {
                            push @{ $result{'comparison'}{$attribute}}, comparison($attribute, $result{'actual'}{$attribute}, $response_expected->{$attribute}->[$k], $xml_document);
                        }
                    }
                }

                push @result, \%result;
            }    
        }
    
        my $result_file_path  = File::Spec->catfile($document_root, 'results', "$application.$test_type.$epoch_seconds.result");
        open(my $result_fh, '>', $result_file_path);
        binmode($result_fh, ':utf8');
        print $result_fh $json->encode(\@result);
        close $result_fh;
        
        close $log_fh if $log_it;

        return {'start_time' => $epoch_seconds*1000, 'num_tests_run' => $test_counter, 'result_file_path' => $result_file_path};    
    }
}

1;
