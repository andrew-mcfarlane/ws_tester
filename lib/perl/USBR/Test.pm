use 5.006;
use strict;
use warnings FATAL => 'all';
use autodie;

{
    package USBR::Test;
    
    use Carp 'confess';
    use Carp::Always;

    use Data::Dumper;
    
    use File::Spec::Unix;
    use File::Spec;
    use File::Basename;
    use HTTP::Cookies;
    use HTTP::Status;
    use WWW::Mechanize;
    use LWP::Protocol::https;
    use URI;
    use JSON::XS;
    
    my $document_root;
    my $lib_directory;

    BEGIN {
        if (not exists($ENV{DOCUMENT_ROOT})) {
            my ($volume, $directories, $file) = File::Spec::Unix->splitpath(File::Spec::Unix->rel2abs(__FILE__));
            my @directories = File::Spec::Unix->splitdir($directories);
            
            # If the last directory part is empty, remove it.
            splice(@directories, -1) if (not defined($directories[-1]) or $directories[-1] eq '');

            # Remove the the last three elements from @directories.
            splice(@directories, -3);
            
            # Put it all back together.
            if ($volume) {
                $document_root = File::Spec::Unix->catdir($volume, @directories);
            }
            else {
                $document_root = File::Spec::Unix->catdir(@directories);
            }
        }
        else {
            my ($volume, $directories, $file) = File::Spec::Unix->splitpath($ENV{DOCUMENT_ROOT});
            my @directories = File::Spec::Unix->splitdir($directories);
                    
            # Put it all back together.
            if ($volume) {
                $document_root = File::Spec::Unix->catdir($volume, @directories, $file);
            }
            else {
                $document_root = File::Spec::Unix->catdir(@directories, $file);
            }
        }
    
        # If File::Spec::Unix->catdir($document_root, 'lib', 'perl') doesn't exist in @INC, add it.
        $lib_directory = File::Spec::Unix->catdir($document_root, 'lib', 'perl');
        my %inc = map { $_ => 1 } @INC;    
        unshift(@INC, $lib_directory) unless exists($inc{$lib_directory});
    }
    
    require USBR::ApplicationSpecification;
    
    *{Regexp::TO_JSON} = sub { return "$_[0]"; };
    
    $| = 1;
    
    my $log_it = 1;
    my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;

    # Object Methods
    sub new {
        my ($class, %args)    = @_;
        
        return bless {}, $class;
    }

    sub get_document_root {
        return $document_root;
    }

    sub get_available_tests {
        my ($self, %args)    = @_;
        
        # Determine the directory holding the test specifications.
        my $test_specifications_directory = File::Spec::Unix->catdir($document_root, 'specifications');

        # Open the test specifications directory for reading.
        opendir my $dir_h, $test_specifications_directory || confess qq{Could not open the tests specifications directory "$test_specifications_directory"};

        # Get a listing of all files in the test specifications directory with the exception of '.' and '..'.
        my @test_specification_files = map { File::Spec::Unix->catfile($test_specifications_directory, $_) } grep { -f File::Spec::Unix->catfile($test_specifications_directory, $_) } readdir($dir_h);
            
        closedir $dir_h;
        
        my @data;
        
        foreach my $i (0 .. $#test_specification_files) {
            # Clean up the path--just in case.
            $test_specification_files[$i] = File::Spec::Unix->canonpath($test_specification_files[$i]);
            
            my ($application, $test_type) = split /\./, File::Basename::basename($test_specification_files[$i]);

            my $application_specifications = USBR::ApplicationSpecification->new($application, $test_type);

            my $application_type = $application_specifications->{'application_type'};
                    
            push @data, {'path' => $test_specification_files[$i], 'application' => $application, 'test_type' => $test_type, 'application_type' => $application_type};
        }    
        
        return \@data;    
    }

    sub get_available_results {
        my ($self, %args)    = @_;

        # Determine the directory holding the test results.
        my $test_results_directory = File::Spec::Unix->catdir($document_root, 'results');

        # Open the test results directory for reading.
        opendir my $dir_h, $test_results_directory || confess qq{Could not open the tests results directory "$test_results_directory"};

        # Get a listing of all files in the test results directory with the exception of '.' and '..'.
        my @test_results_files = map { File::Spec::Unix->catfile($test_results_directory, $_) } grep { -f File::Spec::Unix->catfile($test_results_directory, $_) } readdir($dir_h);

        closedir $dir_h;

        my @data;

        foreach my $i (0 .. $#test_results_files) {
            # Clean up the path--just in case.
            $test_results_files[$i] = File::Spec::Unix->canonpath($test_results_files[$i]);

            my ($application, $test_type, $epoch) = split /\./, File::Basename::basename($test_results_files[$i]);

            push @data, {'path' => $test_results_files[$i], 'application' => $application, 'test_type' => $test_type, 'epoch' => $epoch};
        }

        return \@data;
    
    }
    
    sub start_tests {
        my ($self, %args)    = @_;
        
        # Make sure that the other required parameters for this action were passed.
        my %required_parameters = ('application' => 1, 'test_type' => 1);
        foreach my $name (keys %required_parameters) {
            unless (exists($args{$name})) {
                confess qq{You must pass the "$name" parameter.};
            }
        }
        
        my $epoch_seconds = time();
        
        my ($application, $test_type) = ($args{'application'}, $args{'test_type'});

        my $application_specifications = USBR::ApplicationSpecification->new($application, $test_type);

        my $host = $application_specifications->{'host'};
        my $application_type = $application_specifications->{'application_type'};
        
        my $class_name = lc $application_type;
        $class_name =~ s/_(\w)/\U$1/g;
        $class_name = ucfirst $class_name;
        my $app_spec_class_full_name = "USBR::TestSpecification::$class_name";
        
        (my $require_name = $app_spec_class_full_name . ".pm") =~ s{::}{/}g;
        $require_name = File::Spec->catfile($lib_directory, $require_name);        
        require $require_name;
        
        my $result_class_full_name = "USBR::Result::$class_name";
        
        ($require_name = $result_class_full_name . ".pm") =~ s{::}{/}g;
        $require_name = File::Spec->catfile($lib_directory, $require_name);
        require $require_name;
    
        my $scheme = (exists($application_specifications->{'scheme'}) and defined($application_specifications->{'scheme'}) ? $application_specifications->{'scheme'} : 'http');
        my $port = (exists($application_specifications->{'port'}) and defined($application_specifications->{'port'}) ? $application_specifications->{'port'} : ($scheme eq 'http' ? 80 : 443));
        
        my $test_specification = $app_spec_class_full_name->new($application, $test_type);

        my ($log_file_path, $log_fh);
        if ($log_it) {
            $log_file_path  = File::Spec::Unix->catfile($document_root, 'logs', 'test_runs', "$application.$test_type.$epoch_seconds.log");
            
            eval {
                $log_it = open($log_fh, '>>', $log_file_path);  # If this is not successful, then $log_it will not be evaluated to true anymore.
            };
            
            $log_it = 0 if ($@);
        }

        # Create the http agent.
        my $agent;
        eval {
            $agent = WWW::Mechanize->new(
                timeout                     => 10
                , agent                     => 'usbr-test/1.00'
                , cookie_jar                => HTTP::Cookies->new()
                , ssl_opts                  => {'verify_hostname' => 0}
                , protocols_allowed         => ['http', 'https']
                , requests_redirectable     => ['GET', 'POST', 'PUT', 'DELETE'],
                , autocheck                 => 0
            );
        };
        if ($@) {
            confess qq{Could not create a user agent: $@};
        }

        my $result = $result_class_full_name->new($application, $test_type, $application_specifications, $test_specification, $agent, $log_fh, $epoch_seconds);

        $result->{'application_type'} = $application_type;
                
        return $result;    
    }
    
    sub get_results {
        my ($self, %args)    = @_;
        
        # Make sure that the other required parameters for this action were passed.
        my %required_parameters = ('application' => 1, 'test_type' => 1, 'result_file_path' => 1);
        foreach my $name (keys %required_parameters) {
            unless (exists($args{$name})) {
                confess qq{When getting results, you must pass the "$name" parameter.};
            }
        }
        
        my ($application, $test_type) = ($args{'application'}, $args{'test_type'});

        my $result_file_path  = $args{'result_file_path'};
        my $result_fh;
        eval {
            open($result_fh, '<', $result_file_path);
        };
        if ($@) {
            confess qq{Could not open the results file "$result_file_path": $@};
        }    
        
        my $results_string = do { local $/; <$result_fh> };
        eval { close $result_fh };
        
        confess qq{The test results are empty!} if (length($results_string) == 0);
        
        my $results;
        eval {
            $results = $json->decode($results_string);
        };
        if ($@) {
            confess qq{Could not JSON decode the information inside "$result_file_path": $@};
        }    
        
        eval {
            close $result_fh;
        };

        return $results;    
    }
    
    sub write_log {
        my $self = shift;
        my $fh = shift;
        my @content = @_;
        
        my $timestamp = '[' . scalar(localtime) . ']: ';
        eval {
            print $fh $timestamp, @content;
        };
        if ($@) {
            confess qq{Could not write to log file: $@};
        }
    }    
    
}

__END__

=head1 NAME

USBR::Test - The great new USBR::Test!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use USBR::Test;

    my $foo = USBR::Test->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

Andrew McFarlane, C<< <amcfarlane at usbr.gov> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-usbr-test at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=USBR-Test>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc USBR::Test


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=USBR-Test>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/USBR-Test>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/USBR-Test>

=item * Search CPAN

L<http://search.cpan.org/dist/USBR-Test/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Andrew McFarlane.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of USBR::Test
