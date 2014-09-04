use 5.006000;
use ExtUtils::MakeMaker;

WriteMakefile(

    NAME         => 'Seco::OpsDB',
    VERSION_FROM => 'lib/Seco/OpsDB.pm',
    (

      $] >= 5.005
      ? (

         ABSTRACT => 'Seco OpsDB libaries',
         AUTHOR   => 'tingle2008@gmail.com',
        )

      : () ),

);
