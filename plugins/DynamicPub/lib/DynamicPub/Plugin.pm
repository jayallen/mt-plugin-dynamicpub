package DynamicPub::Plugin;

use strict;
use warnings 'all';
use warnings FATAL => 'all';

use MT::Log::Log4perl qw( l4mtdump );
our $logger = MT::Log::Log4perl->new();

sub init_app {
    my $app = shift;
    my $blog_class = MT->model('blog');
    my $blog_iter = $blog_iter->load_iter();
    while (my $blog = $blog_iter->()) {

    }
    $logger      ||= MT::Log::Log4perl->new(); $logger->trace();
    
}
1