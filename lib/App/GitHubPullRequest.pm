use strict;
use warnings;
use feature qw(say);

package App::GitHubPullRequest;
{
  $App::GitHubPullRequest::VERSION = '0.0.4';
}

# ABSTRACT: Command-line tool to query GitHub pull requests

use JSON qw(decode_json);
use Data::Dumper qw(Dumper);

sub new {
    my ($class) = @_;
    return bless {}, $class;
}


sub run {
    my ($self, @args) = @_;
    my $cmd = scalar @args ? shift @args : 'list';
    my $method = $self->can($cmd);
    return $self->$method(@args) if $method;
    return $self->help(@args);
}


sub help {
    my ($self, @args) = @_;
    print <<"EOM";
$0 [<command> <args> ...]

Where command is one of these:

  list [<state>] Show all pull requests (default)
                     state: open/closed (default: open)
  show <number>  Show details for a specific pull request
  patch <number> Fetch a properly formatted patch for specific pull request
  help           Show this page

EOM
    return 1;
}


sub list {
    my ($self, $state) = @_;
    my $prs = $self->_fetch_all($state);
    say ucfirst($prs->{'state'}) . " pull requests for '" . $prs->{"repo"} . "':";
    unless ( $prs->{'pull_requests'} and @{ $prs->{'pull_requests'} } ) {
        say "No pull requests found.";
        return 0;
    }
    foreach my $pr ( @{ $prs->{"pull_requests"} } ) {
        my $number = $pr->{"number"};
        my $title = $pr->{"title"};
        my $body = $pr->{"body"};
        my $date = $pr->{"updated_at"} || $pr->{'created_at'};
        say join(" ", $number, $date, $title);
    }
    return 0;
}


sub show {
    my ($self, $number, @args) = @_;
    die("Please specify a pull request number.\n") unless $number;
    my $pr = $self->_fetch_one($number);
    die("Unable to fetch pull request $number.\n")
        unless defined $pr;
    {
        my $user = $pr->{'user'}->{'login'};
        my $title = $pr->{"title"};
        my $body = $pr->{"body"};
        my $date = $pr->{"updated_at"} || $pr->{'created_at'};
        say "Date:    $date";
        say "From:    $user";
        say "Subject: $title";
        say "Number:  $number";
        say "\n$body\n" if $body;
    }
    my $comments = $self->_fetch_comments($number);
    foreach my $comment (@$comments) {
        my $user = $comment->{'user'}->{'login'};
        my $date = $comment->{'updated_at'} || $comment->{'created_at'};
        my $body = $comment->{'body'};
        say "-" x 79;
        say "Date: $date";
        say "From: $user";
        say "\n$body\n";
    }
    return 0;
}


sub patch {
    my ($self, $number) = @_;
    die("Please specify a pull request number.\n") unless $number;
    my $patch = $self->_fetch_patch($number);
    die("Unable to fetch patch for pull request $number.\n")
        unless defined $patch;
    print $patch;
    return 0;
}

sub _fetch_comments {
    my ($self, $number) = @_;
    my $pr = $self->_fetch_one($number);
    die("Unable to fetch comments for pull request $number.\n") unless $pr;
    my $comments_url = $pr->{'comments_url'};
    my $comments = decode_json( _fetch_url($comments_url) );
    return $comments;
}

sub _fetch_patch {
    my ($self, $number) = @_;
    my $remote_repo = _find_github_remote();
    my $patch_url = $self->_fetch_one($number)->{'patch_url'};
    return _fetch_url($patch_url);
}

sub _fetch_one {
    my ($self, $number) = @_;
    my $remote_repo = _find_github_remote();
    my $pr_url = 'https://api.github.com/repos/' . $remote_repo . '/pulls/' . $number;
    my $pr = decode_json( _fetch_url($pr_url) );
    return $pr;
}

sub _fetch_all {
    my ($self, $state) = @_;
    $state ||= 'open';
    my $remote_repo = _find_github_remote();
    my $pulls_url = "https://api.github.com/repos/$remote_repo/pulls?state=$state";
    my $pull_requests = decode_json( _fetch_url($pulls_url) );
    return {
        "repo"           => $remote_repo,
        "state"          => $state,
        "pull_requests"  => $pull_requests,
    };
}

sub _find_github_remote {
    # Fetch remotes using git
    my @lines = grep { chomp } qx{git remote -v};
    my $repo;

    # Parse lines from git and use first found github repo
    foreach my $line (@lines) {
        my ($remote, $url, $type) = split /\s+/, $line;
        next unless $type eq '(fetch)'; # only consider fetch remotes
        next unless $url =~ m/github\.com/; # only consider remotes to github
        if ( $url =~ m{github.com[:/](.+)\.git$} ) {
            $repo = $1;
            last;
        }
    }

    # Allow override for testing
    $repo = $ENV{"GITHUB_REPO"} if $ENV{'GITHUB_REPO'};
    die("No valid GitHub remote repo found.\n")
        unless $repo;

    # Fetch repo information
    my $repo_url = "https://api.github.com/repos/$repo";
    my $repo_info = decode_json( _fetch_url( $repo_url ) );
    die("Unable to fetch repo information for $repo_url.\n")
        unless $repo_info;

    # Return the parent repo if repo is a fork
    return $repo_info->{'parent'}->{'full_name'}
        if $repo_info->{'fork'};

    # Not a fork, use this repo
    return $repo;
}

# Fetch the content of a URL
# If URL starts with https://api.github.com/, use github user+password from
# your ~/.gitconfig
sub _fetch_url {
    my ($url) = @_;
    croak("Please specify a URL") unless $url;

    # See if we should use credentials
    my $credentials = "";
    if ( $url =~ m{^https://api.github.com/} ) {
        my $user = qx{git config github.user};
        my $password = qx{git config github.password};
        chomp $user;
        chomp $password;
        if ( $user and $password ) {
            $credentials = qq{-u "$user:$password"};
        }
    }

    my $content = qx{curl -s -w '\%{http_code}' $credentials "$url"};
    my $rc = $? >> 8; # see perldoc perlvar $? entry for details
    die("curl failed to fetch $url with code $rc.\n") if $rc != 0;
    my $code = substr($content, -3, 3, '');
    if ( $code >= 400 ) {
        die("Fetching URL $url failed with code $code:\n$content\n");
    }
    return $content;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

App::GitHubPullRequest - Command-line tool to query GitHub pull requests

=head1 VERSION

version 0.0.4

=head1 SYNOPSIS

    $ prq
    $ prq list closed # not shown by default
    $ prq show 7      # also includes comments
    $ prq patch 7     # can be piped to colordiff if you like colors
    $ prq help

=head1 INSTALLATION

Install it by just typing in these few lines in your shell:

    $ curl -L http://cpanmin.us | perl - --self-upgrade
    $ cpanm App::GitHubPullRequest

=head1 COMMANDS

=head2 help

Displays some help.

=head2 list [<state>]

Shows all pull requests in the given state. State can be either C<open> or
C<closed>.  The default state is C<open>.  This is the default command if
none is specified.

=head2 show <number>

Shows details about the specified pull request number. Also includes
comments.

=head2 patch <number>

Shows the patch associated with the specified pull request number.

=head1 METHODS

=head2 run(@args)

Calls any of the other listed public methods with specified arguments. This
is usually called automatically when you invoke L<prq>.

=head1 CAVEATS

If you don't have C<git config github.user> and C<git config github.password>
set in your git config, it will use unauthenticated API requests, which has
a rate-limit of 60 requests. If you add your user + password info it should
allow 5000 requests before you hit the limit.

You must be standing in a directory that is a git dir and that directory must
have a remote that points to github.com for the tool to work.

=head1 SEE ALSO

=over 4

=item *

L<prq>

=back

=head1 SEMANTIC VERSIONING

This module uses semantic versioning concepts from L<http://semver.org/>.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc App::GitHubPullRequest

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

MetaCPAN

A modern, open-source CPAN search engine, useful to view POD in HTML format.

L<http://metacpan.org/release/App-GitHubPullRequest>

=item *

Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

L<http://search.cpan.org/dist/App-GitHubPullRequest>

=item *

RT: CPAN's Bug Tracker

The RT ( Request Tracker ) website is the default bug/issue tracking system for CPAN.

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-GitHubPullRequest>

=item *

AnnoCPAN

The AnnoCPAN is a website that allows community annotations of Perl module documentation.

L<http://annocpan.org/dist/App-GitHubPullRequest>

=item *

CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

L<http://cpanratings.perl.org/d/App-GitHubPullRequest>

=item *

CPAN Forum

The CPAN Forum is a web forum for discussing Perl modules.

L<http://cpanforum.com/dist/App-GitHubPullRequest>

=item *

CPANTS

The CPANTS is a website that analyzes the Kwalitee ( code metrics ) of a distribution.

L<http://cpants.perl.org/dist/overview/App-GitHubPullRequest>

=item *

CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

L<http://www.cpantesters.org/distro/A/App-GitHubPullRequest>

=item *

CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual overview of the test results for a distribution on various Perls/platforms.

L<http://matrix.cpantesters.org/?dist=App-GitHubPullRequest>

=item *

CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

L<http://deps.cpantesters.org/?module=App::GitHubPullRequest>

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests by email to C<bug-app-githubpullrequest at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-GitHubPullRequest>. You will be automatically notified of any
progress on the request by the system.

=head2 Source Code

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<http://github.com/robinsmidsrod/App-GitHubPullRequest>

  git clone git://github.com/robinsmidsrod/App-GitHubPullRequest.git

=head1 AUTHOR

Robin Smidsrød <robin@smidsrod.no>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Robin Smidsrød.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
