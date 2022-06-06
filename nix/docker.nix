# Builds a docker image containing the emanote executable
{ pkgs, emanote }:

pkgs.dockerTools.buildImage {
  name = "sridca/emanote";
  tag = "latest";
  contents = [
    emanote
    # These are required for the GitLab CI runner
    pkgs.coreutils
    pkgs.bash_5
  ];

  config = {
    WorkingDir = "/data";
    Volumes = {
      "/data" = { };
    };
    Tmpfs = {
      "/tmp" = { };
    };
    Cmd = [ "${emanote}/bin/emanote" ];
  };
}
