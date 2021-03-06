package Reddit;

our $VERSION = '0.20.moose';

use 5.012004;
use Data::Dumper;

use common::sense;

use JSON;
use HTTP::Cookies;
use LWP::UserAgent;

use Moose;

has 'base_url' => (
	is	=> 'ro',
	isa => 'Str',
	default => 'http://www.reddit.com/',
);

has 'api_url' => (
	is	=> 'ro',
	isa => 'Str',
	lazy	=> 1,
	default => sub { $_[0]->base_url . 'api/' },
);

has 'login_api' => (
	is => 'ro',
	isa => 'Str',
	lazy	=> 1,
	default => sub { $_[0]->api_url . 'login' },
); 

has 'submit_api' => (
	is => 'ro',
	isa => 'Str',
	lazy	=> 1,
	default => sub { $_[0]->api_url . 'submit' },	
);

has 'comment_api' => (
	is => 'ro',
	isa => 'Str',
	lazy	=> 1,
	default => sub { $_[0]->api_url . 'comment' },	
);

has 'api_type'	=> (
	is => 'ro',
	isa => 'Str',
	default => 'json',
);

has 'ua' => (
    is  => 'rw',
    isa => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
#    handles => qr/^(?:head|get|post|agent|request.*)/,
	handles => { 
		post				=> 'post',
		agent_cookie_jar 	=> 'cookie_jar' 
	}
);

has 'cookie_jar' => (
	is => 'rw',
	isa => 'HTTP::Cookies',
	lazy => 1,
	default => sub { HTTP::Cookies->new },	
);

has [ 'user_name', 'password', ] => (
	is => 'rw',
	isa => 'Str',
	required => 1,	
	trigger => \&_login,
);

has 'subreddit' => (
	is => 'rw',
	isa => 'Str',
);

has 'modhash' => (
	is => 'rw',
	isa => 'Str',
);

sub _login {
	my $self = shift;
	
	my $response = $self->ua->post($self->login_api,
        {
            api_type    => $self->api_type,
            user        => $self->user_name,
            passwd      => $self->password,
        }
    );

    $self->_set_cookie($response);
}

sub _set_cookie {
    my $self        = shift;
    my $response    = shift;

    $self->cookie_jar->extract_cookies ($response);
    $self->agent_cookie_jar ($self->cookie_jar);
    $self->_parse_modhash ($response);
}

sub _parse_modhash {
    my $self        = shift;
    my $response    = shift;

    my $decoded = from_json ($response->content);
    $self->modhash ($decoded->{json}{data}{modhash});
}

sub _parse_link {
    my $self = shift;
    my $link = shift;

    my ($id) = $link =~ /comments\/(\w+)\//i;
    return 't3_' . $id;
}

# Submit link to reddit
sub submit_link {
    my $self = shift;
    my ($title, $url, $subreddit) = @_;

    my $kind        = 'link';

    my $newpost     = $self->ua->post($self->submit_api,
        {
            uh      => $self->modhash,
            kind    => $kind,
            sr      => $subreddit || $self->subreddit,
            title   => $title,
            r       => $subreddit || $self->subreddit,
            url     => $url,
        }
    );

    my $json_content    = $newpost->content;
    my $decoded         = from_json $json_content;

    #returns link to new post if successful
    my $link = $decoded->{jquery}[18][3][0];
    my $id = $self->parse_link($link);

    return $id, $link;
}

sub submit_story {
    my $self = shift;
    my ($title, $text, $subreddit) = @_;
 
    my $kind        = 'self';
    my $newpost     = $self->post($self->submit_api,
        {
            uh       => $self->modhash,
            kind     => $kind,
            sr       => $subreddit || $self->subreddit,
            r        => $subreddit || $self->subreddit,
            title    => $title,
            text     => $text,
        },
    );

    my $json_content    = $newpost->content;
    my $decoded         = from_json $json_content;

    #returns id and link to new post if successful
    my $link = $decoded->{jquery}[12][3][0];
    my $id = $self->_parse_link($link);

    return $id, $link;
}

sub comment {
    my $self = shift;
    my ($thing_id, $comment) = @_;

    my $response = $self->ua->post($self->comment_api,
        {
            thing_id    => $thing_id,
            text        => $comment,
            uh          => $self->modhash,
        },
    );

    my $decoded = from_json $response->content;
    return $decoded->{jquery}[18][3][0][0]->{data}{id};
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
__END__

=head1 NAME

Reddit - Perl extension for http://www.reddit.com

=head1 SYNOPSIS

  use Reddit;
  
  # instantatiate a new reddit object
  # Automajically handles logging in and cookie handling
  $r = Reddit->new(
      {
          user_name => 'Foo', 
		  password  => 'Bar', 
		  subreddit => 'Perl'
	  }
  );

  # Submit a link
  # $title, $url, $subreddit
  # This overrides a subreddit set duriing instantiation
  $r->submit_link( 'Test', 'http://example.com', 'NotPerl');

  # Submit a Self Post
  # $title, $text, $subreddit
  # This overrides a subreddit set during instantiation
  $r->submit_story( 'Self.test', 'Some Text Here', 'shareCoding');  

  # Post a top level comment to a URL or .self post 
  $r->comment($post_id, $comment);
  
  # Post a reply to a comment
  $r->comment($comment_id, $comment);

=head1 DESCRIPTION

Perl module for interacting with Reddit.

This module is still largely inprogress.

=head2 Requires

  common::sense
  LWP::UserAgent
  JSON
  HTTP::Cookies

  For Testing:
  Data::Dumper

=head2 EXPORT

None.

=head1 Provided Methods

=item B<submit_link($title, $url, $subreddit)>
  $r->submit_link( 'Test', 'http://example.com', 'NotPerl');
This method posts links to the specified subreddit.  The subreddit parameter is optional if it is not set at the time of instantiation
$subreddit is required in one place or the other, subreddit specified here will take precedence over the subreddit specified at time of instantiation.

=item B<submit_story($title, $text, $subreddit)>
  $r->submit_story( 'Self.test', 'Some Text Here', 'shareCoding');
This method makes a Self.post to the specified subreddit.  The subreddit parameter is optional if it is not set at the time of instantiation
$subreddit is required in one place or the other, subreddit specified here will take precedence over the subreddit specified at time of instantiation.

=item B<comment($post_id, $comment)>
   
To post a top level comment to a URL or .self post 
  $r->comment($post_id, $comment);

To post a reply to a comment
  $r->comment($comment_id, $comment);
This methid requires you pass in the cannonical thing ID with the correct thing prefix.
Submit methods return cannonical thing IDs, L<See the FULLNAME Glossary|https://github.com/reddit/reddit/wiki/API> for futher information

The post_id is the alphanumeric string after the name of the subreddit, before the title of the post
The comment_id is the alphanumeric string after the title of the post

=head1 SEE ALSO

L<https://github.com/reddit/reddit/wiki>

=head1 AUTHOR

Jon A, E<lt>info[replacewithat]cyberspacelogistics[replacewithdot]comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by jon

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.

=cut
