
# This file was automatically generated by Dist::Zilla::Plugin::MakeMaker v5.015.
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Generate data structure convenient for producing CLI help/usage",
  "AUTHOR" => "perlancar <perlancar\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Perinci-Sub-To-CLIOptSpec",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Perinci::Sub::To::CLIOptSpec",
  "PREREQ_PM" => {
    "DefHash" => "v1.0.8",
    "Perinci::Object" => 0,
    "Perinci::Sub::GetArgs::Argv" => "0.59",
    "Perinci::Sub::Normalize" => 0,
    "Rinci" => "v1.1.70"
  },
  "TEST_REQUIRES" => {
    "File::Spec" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Perinci::Examples::CLI" => "0.42",
    "Test::More" => 0
  },
  "VERSION" => "0.10",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "DefHash" => "v1.0.8",
  "File::Spec" => 0,
  "IO::Handle" => 0,
  "IPC::Open3" => 0,
  "Perinci::Examples::CLI" => "0.42",
  "Perinci::Object" => 0,
  "Perinci::Sub::GetArgs::Argv" => "0.59",
  "Perinci::Sub::Normalize" => 0,
  "Rinci" => "v1.1.70",
  "Test::More" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



