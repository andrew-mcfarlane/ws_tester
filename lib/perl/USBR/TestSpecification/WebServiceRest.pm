use 5.006;
use strict;
use warnings FATAL => 'all';
use autodie;

{
    package USBR::TestSpecification::WebServiceRest;
    
    use Carp 'confess';
    use Carp::Always;

    use Data::Dumper;
    
    use File::Basename;
    use File::Spec;
    use JSON::XS;
    use JSON::Schema;
        
    $| = 1;
    
    my $log_it = 0;
    my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;

    # Object Methods
    sub new {
        my ($class, $application, $test_type) = @_;

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

        
        my $test_specification_directory =  File::Spec->catdir($document_root, 'specifications');
        my $test_specification_file_path = File::Spec->catfile($test_specification_directory, "$application.$test_type.specifications");
        
        open (my $test_fh, '<', $test_specification_file_path);
        
        my $test_specification = $json->decode(do { local $/; <$test_fh> });
        
        # Load the test specification schema.
        my $schema_directory = File::Spec->catdir($document_root, 'schema');
        my $test_specification_schema_file_path = File::Spec->catfile($schema_directory, 'test_suite.schema.json');

        open (my $schema_fh, '<', $test_specification_schema_file_path);
        
        my $schema = $json->decode(do { local $/; <$schema_fh> });

        my $validator = JSON::Schema->new($schema, format => \%JSON::Schema::FORMATS);
        my $result = $validator->validate($test_specification);
        
        if (!$result) {
            my $message = "Test Suite specification file \"$test_specification_file_path\" is not valid: ";
            foreach my $error ($result->errors) {
                $message .= ": $error";
            }
            
            confess($message);
        }

        return bless $test_specification, $class;                    
    }
}

__END__

1; # End of USBR::TestSpecification::WebServiceRest
