#!/usr/bin/perl

use strict;
use warnings;

use File::Spec;
use File::Spec::Unix;
use File::Basename;
use JSON::XS;

use Data::Dumper;

my $document_root;

my $debug = 1;

sub get_answer {
	my $label = shift;
	my $choice_aref = shift;

	my $last_number = scalar(@{ $choice_aref });
	my $index = -1;

	my $valid = 0;
	while (!$valid) {
		print "Please choose $label\n";
		foreach my $item (@{ $choice_aref }) {
			print "\t$item\n";
		}
		print "\n (1 - $last_number) --> ";
		my $choice = <>;
		chomp $choice;

		if ($choice =~ m/^\d+$/ and $choice >= 1 and $choice <= $last_number) {
			$index = $choice - 1;	
			return $choice_aref->[$index];
		}
		else {
			print qq{"$choice" is not valid--must be an integer between 1 and $last_number.  Try again.\n};
		}
	}
}
	
if (not exists($ENV{DOCUMENT_ROOT})) {
	my ($volume, $directories, $file) = File::Spec::Unix->splitpath(File::Spec::Unix->rel2abs(__FILE__));
	my @directories = File::Spec::Unix->splitdir($directories);
			
	# Remove the the last three elements from @directories.
	splice(@directories, -2);
			
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

# Determine the directory holding the test results.
my $test_results_directory = File::Spec::Unix->catdir($document_root, 'results');
print qq{DEBUG: test results directory: "$test_results_directory"\n};

# Open the test results directory for reading.
opendir my $dir_h, $test_results_directory || die qq{Could not open the tests results directory "$test_results_directory"};

# Get a listing of all files in the test results directory with the exception of '.' and '..'.
my @test_result_files = map { File::Spec::Unix->catfile($test_results_directory, $_) } grep { -f File::Spec::Unix->catfile($test_results_directory, $_) } readdir($dir_h);
			
closedir $dir_h;

my @data;
my %data;
		
foreach my $i (0 .. $#test_result_files) {
	# Clean up the path--just in case.
	$test_result_files[$i] = File::Spec::Unix->canonpath($test_result_files[$i]);
			
	my ($application, $test_type, $epoch, $ending) = split /\./, File::Basename::basename($test_result_files[$i]);
					
	if ($ending and $ending eq 'result') {
		push @data, {'path' => $test_result_files[$i], 'application' => $application, 'test_type' => $test_type, 'epoch' => $epoch};

		$data{$application}{$test_type}{$epoch} =  $test_result_files[$i];
	}
}	

# Display.
if (scalar(@data)) {
	my @application;
	foreach my $application (sort keys %data) {
		push @application, $application;
	}

	my $application = (scalar(@application) > 1 ? get_answer("an application", \@application) : $application[0]);

	my @test_types;
	foreach my $test_type (sort keys %{ $data{$application} }) {
		push @test_types, $test_type;
	}

	my $test_type = (scalar(@test_types) > 1 ? get_answer("an $application test type", \@test_types) : $test_types[0]);

	my @epochs;
	foreach my $epoch (sort keys %{ $data{$application}{$test_type} }) {
		push @epochs, $epoch;
	}

	my $epoch = (scalar(@epochs) > 1 ? get_answer("an $application $test_type run time", \@epochs): $epochs[0]);

	print "$application $test_type test results run on ", scalar(localtime($epoch)), ":\n";

	my $result_file_path;
	foreach my $path (@test_result_files) {
		if ($path =~ m/$application.$test_type.$epoch.result/) {
			$result_file_path = $path;
			last;
		}
	}
	unless (defined($result_file_path)) {
		die qq{Could not find "$application.$test_type.$epoch.result" in: }, join(', ', @test_result_files);
	}

	my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;

	my $result_fh;
	eval {
		open($result_fh, '<', $result_file_path);
	};
	if ($@) {
		die qq{Could not open the results file "$result_file_path": $@};
	}	
		
	my $results_string = do { local $/; <$result_fh> };
	eval { close $result_fh };
		
	die qq{The test results are empty!} if (length($results_string) == 0);
		
	my $results;
	eval {
		$results = $json->decode($results_string);
	};
	if ($@) {
		die qq{Could not JSON decode the information inside "$result_file_path": $@};
	}	
		
	eval {
		close $result_fh;
	};

	# Go through each step's comparisons.
	my $step_counter = 0;
	foreach my $i (0 .. $#$results) {
		$step_counter++;

		my $step_status = 'PASS';
		foreach my $attrib (sort keys %{ $results->[$i]->{'comparison'}}) {
			my $comparison_counter = 0;
			my $last = 0;
			foreach my $j (0 .. $#{ $results->[$i]->{'comparison'}->{$attrib} }) {
				if ($results->[$i]->{'comparison'}->{$attrib}->[$j]->{'status'} eq 'FAIL') {
					$step_status = 'FAIL';
					$last = 1;
					last;
				}
			}

			last if $last;
		}

		print "\tStep $step_counter status: $step_status\n";

		if ($step_status eq 'FAIL') {
			foreach my $attrib (sort keys %{ $results->[$i]->{'comparison'}}) {
				my $comparison_counter = 0;
				my $last = 0;
				foreach my $j (0 .. $#{ $results->[$i]->{'comparison'}->{$attrib} }) {
					if ($results->[$i]->{'comparison'}->{$attrib}->[$j]->{'status'} eq 'FAIL') {
						my $expected = $results->[$i]->{'expected'}->{$attrib}->[$j]->{'value'};
						my $actual = substr($results->[$i]->{'actual'}->{$attrib}, 0, 40);
                                		print qq{\t\t$attrib: Expected: "$expected"; actual: "$actual"\n};
					}
				}
                        }
                }
	}

}
else {
	print "Did not find any test results.\n";
}
