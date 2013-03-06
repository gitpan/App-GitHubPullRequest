
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Command-line tool to query GitHub pull requests",
  "AUTHOR" => "Robin Smidsr\303\270d <robin\@smidsrod.no>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "App-GitHubPullRequest",
  "EXE_FILES" => [
    "bin/pr"
  ],
  "LICENSE" => "perl",
  "NAME" => "App::GitHubPullRequest",
  "PREREQ_PM" => {
    "Data::Dumper" => 0,
    "FindBin" => 0,
    "JSON" => 0,
    "feature" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.0.3",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



