package Reddit::Reader;

use 5.012;
use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use HTTP::Tiny ();
use JSON::XS   ();
use Data::Dumper;

has 'number_of_pages' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => 5
);

has 'result' => (
	'is' => 'ro',
	'isa' => 'HashRef',
	'clearer' => 'clear_result',
	'predicate' => 'has_results',
);

# Subreddit Listing Attributes
has 'subreddits' => (
	'is' => 'rw',
	'isa' => 'ArrayRef[Str]',
);

has 'timeline' => (
	'default' => 'all',
	'is' => 'rw',
	'isa' => enum( [ qw( all year month week day ) ] ),
);

has 'sort' => (
	'default' => 'top',
	'is' => 'rw',
	'isa' => enum( [ qw( new controversial top ) ] ),
);

has 'debug' => (
	'default' => 0,
	'is' => 'rw',
	'isa' => 'Bool',
);

our $VERSION = 0.03;

sub _go_on {
    my ( $self, $counter ) = @_;
    return 1 if $counter < $self->{'number_of_pages'};
}

sub process_result {
    my ( $self, $subreddit, $result ) = @_;
    print Dumper $result;
    $self->{'result'}->{$subreddit} = [] if !exists $self->{'result'}->{$subreddit};
    push @{ $self->{'result'}->{$subreddit} }, $result;
}

sub read {
    my ( $self ) = @_;
    my $timeline = $self->{'timeline'};
    my $sort = $self->{'sort'};
    my $number_of_pages = $self->{'number_of_pages'};
    $self->clear_result();
    my $http = HTTP::Tiny->new( 'agent' => 'Reddit Reader v' . $VERSION );
    my $result;
    foreach my $subreddit ( @{ $self->{'subreddits'} } ) {
        my ( $parsed_response, $page_url, $next, $res );
        
        my $counter = 0;
        $self->{'done'} = 0;
        while ( $self->_go_on($counter) ) {
            $counter++;

            $page_url = "http://www.reddit.com/r/$subreddit/top.json?sort=$sort&t=$timeline";

            if ( $counter > 1 ) {
                $page_url .= "&after=$next&count=" . $counter * 25;
            }

            print "\ngrabbing page $counter: $page_url\n" if $self->debug;

            $res = $http->get($page_url);
            if ( $res->{'status'} != 200 ) {
                return $self->error('non-200 response recieved');
            }

            $parsed_response = JSON::XS::decode_json( $res->{'content'} );
            if ( !exists $parsed_response->{'data'}->{'children'} || ref $parsed_response->{'data'}->{'children'} ne 'ARRAY' ) {
                return $self->error('Reddit API returned an unparsable response');
            }

            $self->{'success'} = 1;

            foreach my $link_hr ( @{ $parsed_response->{'data'}->{'children'} } ) {
                $self->process_result($subreddit, $link_hr->{'data'});
                last if $self->{'done'};
            }
            $next = $parsed_response->{'data'}->{'after'};
            last if !$next;
            last if $self->{'done'};
            sleep 3;
        }

    }
    return 1;
}

sub error {
    my ( $self, $msg ) = @_;
    $self->{'success'}     = 0;
    $self->{'fail_reason'} = $msg;
    return 0;
}


1;
