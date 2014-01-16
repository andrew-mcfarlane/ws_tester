use 5.006;
use strict;
use warnings FATAL => 'all';
use autodie;

{
    package USBR::ApplicationSpecification;
    
    use Carp 'confess';
    use Carp::Always;

    use Data::Dumper;
    
    use File::Basename;
    use File::Spec;
    use JSON::XS;
    use JSON::Schema;
        
    $| = 1;
    
    my $json = JSON::XS->new->pretty->allow_nonref->allow_blessed->convert_blessed;
    
    # Object Methods
    sub new {
        my ($class, $application, $test_type)    = @_;
        
        my $document_root;
        if (not exists($ENV{DOCUMENT_ROOT})) {
            my ($volume, $directories, $file) = File::Spec->splitpath(File::Spec->rel2abs(__FILE__));
            my @directories = File::Spec->splitdir($directories);
            
            # Remove the the last four elements from @directories.
            splice(@directories, -4);
            
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

        # Open the file that describes some application/site-specific information
        my $application_specification_directory = File::Spec->catdir($document_root, 'app');
        my $application_specification_file_path = File::Spec->catfile($application_specification_directory, "$application.app");
        
        open (my $application_fh, '<', $application_specification_file_path);
        
        # The application specification file is in JSON format--slurp it up and decode it into a hash.
        my $application_specification = $json->decode(do { local $/; <$application_fh> });

        # Load the test specification schema.
        my $schema_directory = File::Spec->catdir($document_root, 'schema');
        my $application_specification_schema_file_path = File::Spec->catfile($schema_directory, 'app.schema.json');
        
        open (my $schema_fh, '<', $application_specification_schema_file_path);
        
        my $schema = $json->decode(do { local $/; <$schema_fh> });

        my $validator = JSON::Schema->new($schema, format => \%JSON::Schema::FORMATS);
        my $result = $validator->validate($application_specification);
        
        if (!$result) {
            my $message = "Application specification file \"$application_specification_file_path\" is not valid: ";
            foreach my $error ($result->errors) {
                $message .= ": $error";
            }
            
            confess($message);
        }
        
        return bless $application_specification, $class;    
    }
}

__END__

1; # End of USBR::ApplicationSpecification
