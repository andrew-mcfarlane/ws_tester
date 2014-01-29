use 5.006;
use strict;
use warnings FATAL => 'all';
use autodie;

{
    package USBR::Result::WebSite;
    
    use Carp 'confess';
    use Carp::Always;

    use Data::Dumper;
    
    use File::Basename;
    use File::Spec;
    use JSON::XS;
    use JSON::Schema;
    use HTML::TreeBuilder::XPath;
    use Time::HiRes qw(gettimeofday tv_interval);
    use Scalar::Util;
        
    $| = 1;
    
    my $log_it = 0;
    my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;
    
    my $debug = 1;
    
    # Convenience methods.
    sub comparison {
        my $attribute_name = shift;
        my $value_actual = shift;
        my $actual_comparison_hash_ref = shift;
        my $document = shift;
        my $agent = shift;

        $value_actual = '' if (!defined($value_actual));
                        
        my $answer = {'status' => 'PASS'};
        
        my $variety = $actual_comparison_hash_ref->{'variety'};
        my $value_expected = $actual_comparison_hash_ref->{'value'};

        my $expression = (exists($actual_comparison_hash_ref->{'expression'}) ? $actual_comparison_hash_ref->{'expression'} : undef);
        my $operator = (exists($actual_comparison_hash_ref->{'operator'}) ? $actual_comparison_hash_ref->{'operator'} : undef);
        my $name = (exists($actual_comparison_hash_ref->{'name'}) ? $actual_comparison_hash_ref->{'name'} : undef);
                 
        if ($variety eq 'logical') {
            my $command = (Scalar::Util::looks_like_number($value_expected) ? "$value_actual $operator $value_expected" : qq{"$value_actual" $operator "$value_expected"});
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
            $answer->{'display'} = $value_actual;
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
                        $answer->{'display'} = $value_act;
                        last;
                    }
                }

                if (!$found_header_name) {
                    my $message = qq{Could not find a "$name" header};
                    $answer->{'status'} = 'FAIL';
                    $answer->{'message'} = $message;
                    $answer->{'display'} = $value_actual->as_string;
                }
            }
            elsif (defined(ref($value_actual)) and ref($value_actual)) {
                confess qq{Comparing against an actual value of "}, ref($value_actual), qq{" objects has not yet been implemented};
            }
            elsif ($value_actual !~ m/$value_expected/) {
                my $message = qq{Got a response $attribute_name value of "$value_actual", which does not match the $variety expression "$value_expected"};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
                $answer->{'display'} = $value_actual;
            }
            else {
                $answer->{'display'} = $value_expected;
            }
        }
        elsif ($variety eq 'xpath') {
            $document->parse($value_actual);

            my @nodes = $document->findnodes_as_strings($expression);
            my $num_nodes = (@nodes and scalar(@nodes) ? scalar(@nodes) : 0);
            my $all_same_values = 1;
            if ($num_nodes != 1) {
                # Compromise here.  If all the node values are the same, then we'll say this is a PASS.
                foreach my $i (1 .. $#nodes) {
                    if ($nodes[$i] ne $nodes[$i - 1]) {
                        $all_same_values = 0;
                        last;
                    }
                }

                if (!$all_same_values) {
                    my $message = qq{Found $num_nodes response $attribute_name nodes matching the $variety expression "$expression":  Expected exactly one match};
                    $answer->{'status'} = 'FAIL';
                    $answer->{'message'} = $message;
                    $answer->{'display'} = join('; ', @nodes);
                }
                else {
                    $answer->{'display'} = $nodes[0];
                }
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

                $answer->{'display'} = $value_actual;
            }
        }
        elsif ($variety eq 'image') {
            my ($attribute, $val) = split /\=/, $value_expected;
            my @images = $agent->find_all_images($attribute => $val);
            my $num_images = scalar(@images);
            
            if ($num_images != 1) {
                my $message = qq{Found $num_images images where "$attribute" equals "$val": Expected exactly one match};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
                $answer->{'display'} = join(', ', map { $_->url_abs } @images);
            }
            else {
                eval {
                    $answer->{'display'} = $images[0]->$attribute();
                };
            }
        }
        elsif ($variety eq 'link') {
            my ($attribute, $val) = split /\=/, $value_expected;
            my @links = $agent->find_all_links($attribute => $val);
            my $num_links = scalar(@links);

            if ($num_links != 1) {
                my $message = qq{Found $num_links links where "$attribute" equals "$val": Expected exactly one match};
                $answer->{'status'} = 'FAIL';
                $answer->{'message'} = $message;
                $answer->{'display'} = join(', ', map { $_->url_abs } @links);
            }
            else {
                eval {
                    $answer->{'display'} = $links[0]->$attribute();
                };
            }
        }
        else {
            confess qq{The "$variety" comparison type is not yet implemented};
        }

        return $answer;
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

        my @results;

        $agent->cookie_jar->clear();

        my $test_counter = 0;
        foreach my $i (0 .. $#$test_specification) {
            $test_counter++;

            my %test;

            $test{'title'} = $test_specification->[$i]->{'title'};

            my $step_counter = 0;
            foreach my $j ( 0 .. $#{ $test_specification->[$i]->{'steps'} }) {
                $step_counter++;
            
                my $request = $test_specification->[$i]->{'steps'}->[$j]->{'request'};

                my %step;

                $step{'request'}{'variety'} = $request->{'variety'};
                
                my ($start, $response);
                
                if ($request->{'variety'} eq 'uri') {
                
                    if (!exists($request->{'target'}->{'uri'})) {
                        confess qq{Invalid request target--you did not specify a request target uri value};
                    }

                    my $uri = URI->new();
                    $uri->scheme($request->{'target'}->{'uri'}->{'scheme'});
                    $uri->host($request->{'target'}->{'uri'}->{'host'});        

                    if (exists($request->{'target'}->{'uri'}->{'port'})) {
                        $uri->port($request->{'target'}->{'uri'}->{'port'});        
                    }
                    
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

                    $step{'request'}{'uri'} = $uri;
                                
                    if (exists($application_specifications->{'authorization'}) and defined($application_specifications->{'authorization'})) {
                        if ($application_specifications->{'authorization'}->{'method'} eq 'X-Authorization') {
                            $agent->default_header('X-Authorization' => $application_specifications->{'authorization'}->{'key'});
                        }
                    }
                
                    my $method_name = lc $request->{'target'}->{'method'};

                    $step{'request'}{'method_name'} = $method_name;
                        
                    # Make the HTTP call and get the response.
                    $start = [gettimeofday];
                    eval {
                        if (!defined($test_specification->[$i]->{'request'}->{'body'})) {
                            $response = $agent->$method_name($uri);
                        }
                        else {
                            $response = $agent->$method_name($uri, 'Content' => $test_specification->[$i]->{'request'}->{'body'});
                        }
                    };
                    if ($@) {
                        #confess qq{Test # $test_counter step # $step_counter could not be executed: $@};
                        $step{'actual'}{'error'} = qq{Test # $test_counter step # $step_counter could not be executed: $@};
                        last;
                    }
                }
                elsif ($request->{'variety'} eq 'form') {
                    $start = [gettimeofday];

                    if (exists($request->{'target'}->{'form_id'})) {
                        $step{'request'}{'locator'} = 'form_id';
                        $step{'request'}{'form_id'} = $request->{'target'}->{'form_id'};
                    }
                    elsif (exists($request->{'target'}->{'form_name'})) {
                        $step{'request'}{'locator'} = 'form_name';
                        $step{'request'}{'form_name'} = $request->{'target'}->{'form_name'};
                    }
                                        
                    eval {
                        $response = $agent->submit_form(%{ $request->{'target'} });
                    };
                    if ($@) {
                        #confess qq{Test # $test_counter step # $step_counter could not be executed: $@};
                        $step{'actual'}{'error'} =  qq{Test # $test_counter step # $step_counter could not be executed: $@};
                        last;
                    }
                }
                else {
                    confess qq{The "$request->{'variety'}" request type has not yet been implemented};
                }
                
                $step{'actual'}{'timestamp'}    = POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($start->[0]));
                
                $step{'actual'}{'time'}        = tv_interval ($start, [gettimeofday]);                            
                $step{'actual'}{'code'}         = $response->code;
                $step{'actual'}{'uri'}         = $response->base->as_string;
                $step{'actual'}{'headers'}    = $response->headers;
                $step{'actual'}{'content'}    = $response->decoded_content;
                $step{'actual'}{'format'}        = $response->header('Content-Type') || $response->content_type();
                $step{'actual'}{'size'}        = $response->header('Content-Length') || length($response->content);
                $step{'actual'}{'title'}        = $agent->title;
                                
                # Compare the these actual results with the expected results.
                
                my $response_expected = $test_specification->[$i]->{'steps'}->[$j]->{'response_expected'};
                
                my $document =     HTML::TreeBuilder::XPath->new;
                
                if (index($step{'actual'}{'format'}, 'html') > -1) {
                    eval {
                        $document->parse($response->content);
                    };
                    if ($@) {
                        push @{ $step{'comparison'}{'format'} }, { 'status' => 'FAIL', 'display' => $step{'actual'}{'format'}, 'message' => "The response format is $step{'actual'}{'format'} and not html as expected" };
                    }
                    else {
                        push @{ $step{'comparison'}{'format'} }, { 'status' => 'PASS', 'display' => $step{'actual'}{'format'} };

                        # for each href and src tag, make sure that there values are absolute.
			my $temp_content = $step{'actual'}{'content'};
                        while ($step{'actual'}{'content'} =~ m/(href|src)\="([^"]+)"/gi) {
                            my $old = $2;
                            my $uri = URI->new_abs($old, $response->base);
                            $temp_content =~ s/$old/$uri/g;
                        }

                        # Remove some characters.
                        $temp_content =~ s/[\t\r\n]+//g;
                        $temp_content =~ s/\s\s/ /g;

                        $step{'actual'}{'content'} = $temp_content;
                    }
                }
                else {
                    push @{ $step{'comparison'}{'format'} }, { 'status' => 'FAIL', 'display' => $step{'actual'}{'format'}, 'message' => "The response format is $step{'actual'}{'format'} and not html as expected" };
                }
                                                
                # Save the expected results for displaying later.
                foreach my $attrib_name (keys %{ $response_expected }) {
                    foreach my $k (0 .. $#{ $response_expected->{$attrib_name} }) {
                        my $thingy = $response_expected->{$attrib_name}->[$k];
                        foreach my $thingy_attribute (keys %{ $thingy }) {
                            $step{'expected'}{$attrib_name}[$k]{$thingy_attribute} = $thingy->{$thingy_attribute};
                        }
                    }
                }
                
                my @typical_attributes = ('headers', 'time', 'format', 'code', 'format', 'content', 'size', 'title');
                
                foreach my $attribute (@typical_attributes) {                                    
                    if (defined($response_expected->{$attribute})) { 
                        foreach my $k ( 0 .. $#{ $response_expected->{$attribute} }) {
                            push @{ $step{'comparison'}{$attribute}}, comparison($attribute, $step{'actual'}{$attribute}, $response_expected->{$attribute}->[$k], $document, $agent);
                        }
                    }
                }

                push @{ $test{'steps'} }, \%step;
            }    

            push @results, \%test;
        }
    
        my $result_file_path  = File::Spec->catfile($document_root, 'results', "$application.$test_type.$epoch_seconds.result");
        open(my $result_fh, '>', $result_file_path) or confess qq{Could not open result file "$result_file_path" for writing: $!};
        binmode($result_fh, ':utf8');
        print $result_fh $json->encode(\@results);
        close $result_fh;
        
        close $log_fh if $log_it;

        return {'start_time' => $epoch_seconds*1000, 'result_file_path' => $result_file_path};    
    }

}

__END__

1; # End of USBR::Result::WebSite

