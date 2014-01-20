#!/usr/bin/perl

use strict;
use warnings;
use autodie;

use JSON::XS;
use CGI;
use File::Basename;
use File::Spec::Functions;

use lib File::Spec->catdir(File::Basename::dirname(File::Spec->rel2abs(__FILE__)), '..', 'lib', 'perl');

use USBR::Test;

my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;
my $cgi = CGI->new;

unless (exists $ENV{'GATEWAY_INTERFACE'}) {
	#$cgi->param('action', 'request_test_info');
	$cgi->param('action', 'execute_tests');
	#$cgi->param('action', 'request_results');
	$cgi->param('application', 'ZEITOnline');
	$cgi->param('test_type', 'sanity');
}

my %params = $cgi->Vars;

print $cgi->header(
	-type => 'application/json',
	-charset => 'utf-8',
);

# Make sure that the 'action' parameter was passed.
if (not exists($params{'action'})) {
	print $json->encode({'status' => 'error', 'code' => 400, 'message' => qq{You must pass the "action" parameter.}});
	exit 0;
}

# Make sure that the value of the 'action' parameter is valid.
my %valid_actions = ('request_test_info' => 1, 'execute_tests' => 1, 'request_results' => 1);
unless (exists($valid_actions{$params{'action'}})) {
	my $message = qq{The "action" parameter value "$params{'action'}" is not supported--use one of the following: } . join(', ', keys(%valid_actions));
	print $json->encode({'status' => 'error', 'code' => 400, 'message' => $message});
	exit 0;
}

# Do work based on the value of the 'action' parameter.
if ($params{'action'} eq 'request_test_info') {
	my $test = USBR::Test->new();
	my ($data1, $data2, $document_root);
	eval {
		$data1 = $test->get_available_tests(%params);
	};
	
	if ($@) {
		print $json->encode({'status' => 'error', 'code' => 400, 'message' => $@});
	}
	else {
                eval {
			$data2 = $test->get_available_results(%params);
		};
		if ($@) {
			 print $json->encode({'status' => 'error', 'code' => 400, 'message' => $@});
		}

                $document_root = $test->get_document_root();

		print $json->encode({'status' => 'success', 'code' => 200, 'tests' => $data1, 'results' => $data2, 'document_root' => $document_root});
	}
}
elsif ($params{'action'} eq 'execute_tests') {
	my $test = USBR::Test->new();
	my $data;
	eval {
		$data = $test->start_tests(%params);
	};
	
	if ($@) {
		print $json->encode({'status' => 'error', 'code' => 400, 'message' => $@});
	}
	else {
		print $json->encode({'status' => 'success', 'code' => 200, 'data' => $data});
	}
}
elsif ($params{'action'} eq 'request_results') {
	my $test = USBR::Test->new();
	my $data;
	eval {
		$data = $test->get_results(%params);
	};
	
	if ($@) {
		print $json->encode({'status' => 'error', 'code' => 400, 'message' => $@});
	}
	else {
		print $json->encode({'status' => 'success', 'code' => 200, 'data' => $data});
	}
}
else {
	print $json->encode({'status' => 'error', 'code' => 400, 'message' => qq{The "$params{'action'}" action has not yet been implemented}});
}

exit;
