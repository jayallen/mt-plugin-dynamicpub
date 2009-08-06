# Movable Type (r) Open Source (C) 2001-2008 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id: Viewer.pm 2877 2008-08-01 01:43:09Z bchoate $

package MT::App::Viewer;

use strict;
use warnings 'all';
use warnings FATAL => 'all';
use base qw( MT::App );

use MT::Entry;
use MT::Template;
use MT::Template::Context;
use MT::Promise qw(delay);

our $logger;
sub get_logger {    
    return $logger if $logger;
    require MT::Log;
    import MT::Log::Log4perl qw(l4mtdump);
    $logger = MT::Log::Log4perl->new();
}

sub init {
    my $app = shift;
    $app->SUPER::init(@_) or return;
    $app->{default_mode} = 'main';
    $app->add_methods( 'main' => \&view, );
    $logger = get_logger();
    return $app;
}

my %view_handlers = (
    'index'      => \&_view_index,
    'Individual' => \&_view_entry,
    'Page'       => \&_view_entry,
    'Category'   => \&_view_category,
    'Author'     => \&_view_author,
    '*'          => \&_view_archive,
);

sub resolve_uri {
    my ($app, $uri, $blog_id) = @_;
    return unless defined $uri;
    $uri =~ s!/$!!;
    #     $path = $this->escape($path);

    #     # resolve for $path -- one of:
    #     #      /path/to/file.html
    #     #      /path/to/index.html
    #     #      /path/to/
    #     #      /path/to

    my $cfg = $app->config;
    my $idx = $cfg->IndexBasename   || 'index';
    my $ext = ($app->blog ? $app->blog->file_extension : '') || '';
    $idx = join('.', $idx, $ext) if $ext ne '';
    my $uri_idx = ($uri =~ m!\Q/$idx\E$!) ? '' : join('/', $uri, $idx);

    my @urls = ($uri);
    unshift @urls, $uri_idx if $uri_idx;

    $logger->debug('Attempting to load fileinfo for @urls ', l4mtdump(\@urls));
    require MT::FileInfo;
    my @fi = MT::FileInfo->load({
            url     => \@urls,
            (defined $blog_id ? (blog_id => $blog_id) : ()),
    });
    unless ( @fi ) {
        @urls = map { { url => { like => "$_%" } }, '-or' } @urls;
        pop @urls;
        $logger->debug('\@urls ', l4mtdump(\@urls));
        @fi = MT::FileInfo->load([ @urls ]);
    }
    foreach my $fi ( @fi ) {
        $logger->debug(sprintf 'Matching %s to %s or %s', $fi->url, $uri, $uri_idx);
        
        if ($fi->url =~ m{^($uri|$uri_idx)(\.[a-z0-9]+)?$}) {
            return $fi;
        }
    }
    $logger->warn("No matching fileinfo found for $uri");
    return;
    # return $uri;

    # $logger->debug('\@fi: ', l4mtdump(\@fi));

    # my @foo = MT::Foo->load(
            # [
            #     { foo => { like => 'bar%' } },
            #     '-or',
            #     { foo => { like => 'bar%' } }
            # ]
    #     => -or => { foo => { like => 'bar%' } } ] );
    # my @foo = MT::Foo->load( { foo => { like => 'bar%' } });


    #     foreach ( array($path, urldecode($path), urlencode($path)) as $p ) {
    #         $sql = "
    #             select *
    #               from mt_blog, mt_template, mt_fileinfo
    #               left outer join mt_templatemap on templatemap_id = fileinfo_templatemap_id
    #              where fileinfo_blog_id = $blog_id
    #                    and ((fileinfo_url = '%1\$s' or fileinfo_url = '%1\$s/') or (fileinfo_url like '%1\$s/$escindex%%'))
    #                and blog_id = fileinfo_blog_id
    #                and template_id = fileinfo_template_id
    #                and template_type != 'backup'
    #              order by length(fileinfo_url) asc
    #         ";
    #         $rows = $this->get_results(sprintf($sql,$p), ARRAY_A);
    #         if ($rows) {
    #             break;
    #         }
    #     }
    #     $path = $p;
    #     if (!$rows) return null;
    # 
    #     $found = false;
    #     foreach ($rows as $row) {
    #         $fiurl = $row['fileinfo_url'];
    #         if ($fiurl == $path) {
    #             $found = true;
    #             break;
    #         }
    #         if ($fiurl == "$path/") {
    #             $found = true;
    #             break;
    #         }
    #         $ext = $row['blog_file_extension'];
    #         if (!empty($ext)) $ext = '.' . $ext;
    #         if ($fiurl == ($path.'/'.$index.$ext)) {
    #             $found = true; break;
    #         }
    #         if ($found) break;
    #     }
    #     if (!$found) return null;
    #     $data = array();
    #     foreach ($row as $key => $value) {
    #         if (preg_match('/^([a-z]+)/', $key, $matches)) {
    #             $data[$matches[1]][$key] = $value;
    #         }
    #     }
    #     $this->_blog_id_cache[$data['blog']['blog_id']] =& $data['blog'];
    #     return $data;
    # }
    
}

sub view {
    my $app = shift;
    $logger->trace();
    my $R = MT::Request->instance;
    $R->stash( 'live_view', 1 );

    ## Process the path info.
    my $blog_id = $app->param('blog_id');
    my $uri     = $app->param('uri') || $ENV{REQUEST_URI} || $app->path_info;
    $uri = "/$uri" unless substr($uri, 0, 1) eq '/';

    $logger->debug('uri: ', $uri);
    $logger->debug('blog_id: ', $blog_id||'NONE');
    my $fileinfo = $app->resolve_uri($uri, $blog_id);
    $logger->debug('THE FILEINFO: ', l4mtdump($fileinfo));
    
    $blog_id = $fileinfo->blog_id if $fileinfo;

    ## Check ExcludeBlogs and IncludeBlogs to see if this blog is
    ## private or not.
    my $cfg = $app->config;
    $app->{__blog_id} = $blog_id;

    require MT::Blog;
    my $blog = $app->{__blog} = MT::Blog->load($blog_id)
        or return $app->error(
        $app->translate( "Loading blog with ID [_1] failed", $blog_id ) );

    # my $idx = $cfg->IndexBasename   || 'index';
    # my $ext = $blog->file_extension || '';
    # $idx .= '.' . $ext if $ext ne '';
    # 
    # my @urls = ($uri);
    # if ( $uri !~ m!\Q/$idx\E$! ) {
    #     push @urls, $uri . '/' . $idx;
    # }
    # 
    # require MT::FileInfo;
    # my @fi = MT::FileInfo->load({   blog_id => $blog_id,
    #         url     => \@urls
    # });
    # if (@fi) {
    #     if ( my $tmpl = MT::Template->load( $fi[0]->template_id ) ) {
    #         $logger->debug('TEMPLATE TYPE: ', $tmpl->type);
    #         my $handler = $view_handlers{ $tmpl->type };
    #         $handler ||= $view_handlers{'*'};
    #         return $handler->( $app, $fi[0], $tmpl );
    #     }
    # }
    my $tmpl;
    if ($fileinfo) {
        if ( $tmpl = MT::Template->load( $fileinfo->template_id ) ) {
            $logger->debug('TEMPLATE TYPE: ', $tmpl->type);
            my $handler = $view_handlers{ $tmpl->type };
            $handler ||= $view_handlers{'*'};
            return $handler->( $app, $fileinfo, $tmpl );
        }
    }
    if ($tmpl = MT::Template->load(
            {   blog_id => $blog_id,
                type    => 'dynamic_error'
            }
        )
        )
    {
        my $ctx = $tmpl->context;
        $ctx->stash( 'blog',    $blog );
        $ctx->stash( 'blog_id', $blog_id );
        return $tmpl->output();
    }
    return $app->error("File not found");
}

my %MimeTypes = (
    css  => 'text/css',
    txt  => 'text/plain',
    rdf  => 'text/xml',
    rss  => 'text/xml',
    xml  => 'text/xml',
    js   => 'text/javascript',
    json => 'text/javascript+json',
);

sub _view_index {
    my $app = shift;
    my ( $fi, $tmpl ) = @_;
    $logger->trace();
    $logger->debug('FileInfo: ', l4mtdump($fi));
    $logger->debug('Template: ', l4mtdump($tmpl));

    my $q = $app->param;
    
    my $ctx = $tmpl->context;
    if ( $tmpl->text =~ m/<MT:?Entries/i ) {
        my $limit  = $q->param('limit');
        my $offset = $q->param('offset');
        if ( $limit || $offset ) {
            $limit ||= 20;
            my %arg = (
                'sort'    => 'authored_on',
                direction => 'descend',
                limit     => $limit,
                ( $offset ? ( offset => $offset ) : () ),
            );
            my @entries = MT::Entry->load(
                {   blog_id => $app->{__blog_id},
                    status  => MT::Entry::RELEASE()
                },
                \%arg
            );
            $ctx->stash( 'entries', delay( sub { \@entries } ) );
        }
    }
    my $out = $tmpl->build($ctx)
        or return $app->error(
        $app->translate( "Template publishing failed: [_1]", $tmpl->errstr )
        );
    ( my $ext = $tmpl->outfile ) =~ s/.*\.//;
    my $mime = $MimeTypes{$ext} || 'text/html';
    $app->send_http_header($mime);
    $app->print($out);
    $app->{no_print_body} = 1;
    1;
}

sub _view_archive {
    my $app = shift;
    my ($fileinfo, $tmpl) = @_;
    if ($fileinfo->templatemap_id) {
        require MT::TemplateMap;
        my $map = MT::TemplateMap->load($fileinfo->templatemap_id);
        my $archive_type = $map->archive_type || '';
        if ( $archive_type =~ m{(Daily|Weekly|Monthly|Yearly)} ) {
            (my $spec = $fileinfo->url) =~ s{^.*?/(\d{4}(/\d{2}(/\d{2})?)?).*}{$1};
            $logger->debug('SPEC: ', $spec);
            _view_date_archive($app, $spec);
        }
        elsif ( $archive_type eq 'Individual' ) {
            _view_entry($app, $fileinfo->entry_id, $tmpl);
        }
        elsif ( $archive_type eq 'Page' ) {
        }
        elsif ( $archive_type eq 'Category' ) {
        }
    }
}
sub _view_date_archive {
    my $app = shift;
    my ($spec) = @_;
    my ( $start, $end, $at );
    my $ctx = MT::Template::Context->new;
    my ($y, $m, $d);
    if ( $spec =~ m!^(\d{4})/(\d{2})/(\d{2})! ) {
        ( $y, $m, $d ) = ( $1, $2, $3 );
        ( $start, $end )
            = ( $y . $m . $d . '000000', $y . $m . $d . '235959' );
        $at = $ctx->{current_archive_type} = 'Daily';
    }
    elsif ( $spec =~ m!^(\d{4})/(\d{2})! ) {
        ( $y, $m ) = ( $1, $2 );
        my $days = MT::Util::days_in( $m, $y );
        ( $start, $end )
            = ( $1 . $2 . '01000000', $1 . $2 . $days . '235959' );
        $at = $ctx->{current_archive_type} = 'Monthly';
    }
    elsif ( $spec =~ m!^week/(\d{4})/(\d{2})/(\d{2})! ) {
        ( $y, $m, $d ) = ( $1, $2, $3 );
        ( $start, $end )
            = MT::Util::start_end_week( "$1$2${3}000000", $app->{__blog} );
        $at = $ctx->{current_archive_type} = 'Weekly';
    }
    else {
        return $app->error( $app->translate("Invalid date spec") );
    }
    $ctx->{current_timestamp}     = $start;
    $ctx->{current_timestamp_end} = $end;
    my @entries = MT::Entry->load({   authored_on => [ $start, $end ],
            blog_id     => $app->{__blog_id},
            status      => MT::Entry::RELEASE()
        },
        { range => { authored_on => 1 } }
    );
    $ctx->stash( 'entries', delay( sub { \@entries } ) );
    require MT::TemplateMap;
    my $map = MT::TemplateMap->load({   archive_type => $at,
            blog_id      => $app->{__blog_id},
            is_preferred => 1
        }
    ) or return $app->error( $app->translate("Can't load templatemap") );
    my $tmpl = MT::Template->load( $map->template_id )
        or return $app->error(
        $app->translate( "Can't load template [_1]", $map->template_id ) );
    my $out = $tmpl->build($ctx)
        or return $app->error(
        $app->translate( "Archive publishing failed: [_1]", $tmpl->errstr ) );
    $out;
}

sub _view_entry {
    my $app = shift;
    my ( $entry_id, $template ) = @_;
    my $entry = MT::Entry->load($entry_id)
        or return $app->error(
        $app->translate( "Invalid entry ID [_1]", $entry_id ) );
    return $app->error(
        $app->translate( "Entry [_1] is not published", $entry_id ) )
        unless $entry->status == MT::Entry::RELEASE();
    my $ctx = MT::Template::Context->new;
    $ctx->{current_archive_type} = 'Individual';
    $ctx->{current_timestamp}    = $entry->authored_on;
    $ctx->stash( 'entry', $entry );
    my %cond = (
        EntryIfAllowComments => $entry->allow_comments,
        EntryIfCommentsOpen  => $entry->allow_comments eq '1',
        EntryIfAllowPings    => $entry->allow_pings,
        EntryIfExtended      => $entry->text_more ? 1 : 0,
    );
    require MT::TemplateMap;
    my $tmpl;

    if ($template) {
        $tmpl = $template if ref $template and $template->isa('MT::Template');
        $tmpl ||= MT::Template->load(
            {   name    => $template,
                blog_id => $app->{__blog_id}
            }
            )
            or return $app->error(
            $app->translate( "Can't load template [_1]", $template ) );
    }
    else {
        my $map = MT::TemplateMap->load(
            {   archive_type => 'Individual',
                blog_id      => $app->{__blog_id},
                is_preferred => 1
            }
            )
            or
            return $app->error( $app->translate("Can't load templatemap") );
        $tmpl = MT::Template->load( $map->template_id )
            or return $app->error(
            $app->translate( "Can't load template [_1]", $map->template_id )
            );
    }
    my $out = $tmpl->build( $ctx, \%cond )
        or return $app->error(
        $app->translate( "Archive publishing failed: [_1]", $tmpl->errstr ) );
    $out;
}

sub _view_category {
    my $app = shift;
    my ($cat_id) = @_;
    require MT::Category;
    my $cat = MT::Category->load($cat_id)
        or return $app->error(
        $app->translate( "Invalid category ID '[_1]'", $cat_id ) );
    my ( $start, $end, $at );
    my $ctx = MT::Template::Context->new;
    $ctx->stash( 'archive_category', $cat );
    $ctx->{current_archive_type} = 'Category';
    require MT::Placement;
    my @entries = MT::Entry->load(
        {   blog_id => $app->{__blog_id},
            status  => MT::Entry::RELEASE()
        },
        {   'join' =>
                [ 'MT::Placement', 'entry_id', { category_id => $cat_id } ]
        }
    );
    $ctx->stash( 'entries', delay( sub { \@entries } ) );
    require MT::TemplateMap;
    my $map = MT::TemplateMap->load({   archive_type => 'Category',
            blog_id      => $app->{__blog_id},
            is_preferred => 1
    });
    my $tmpl = MT::Template->load( $map->template_id )
        or return $app->error(
        $app->translate( "Can't load template [_1]", $map->template_id ) );
    my $out = $tmpl->build($ctx)
        or return $app->error(
        $app->translate( "Archive publishing failed: [_1]", $tmpl->errstr ) );
    $out;
}

1;
__END__

=head1 NAME

MT::App::Viewer

=head1 METHODS

=head2 $app->init()

This method is called automatically during construction. It calls
L<MT::App/init>, regsters the C<view> method and sets the object's
I<default_mode>.

=head2 $app->view()

This generic method views a template interpolated in the appropriate context.

=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut
