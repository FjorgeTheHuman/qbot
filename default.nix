{ stdenv, lib, symlinkJoin, makeWrapper
, pkg-config, git
, ruby_3_0, bundler, bundix, defaultGemConfig, bundlerEnv
, libsodium, libopus, ffmpeg, youtube-dl
, imagemagick7, pango
, sqlite, zlib, shared-mime-info, libxml2, libiconv
, figlet }:

let
  ruby' = ruby_3_0;

  bundler' = bundler.override { ruby = ruby'; };

  bundix' = bundix.override { bundler = bundler'; };

  bundlerEnv' = bundlerEnv.override {
    ruby = ruby';
    bundler = bundler';
  };

  imagemagick7' = imagemagick7.overrideAttrs (oa: with oa; {
    buildInputs = oa.buildInputs ++ [ pango ];
  });

  env = bundlerEnv' {
    name = "qbot-bundler-env";

    gemfile  = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset   = ./gemset.nix;
    gemdir   = ./.;

    ruby = ruby';
    bundler = bundler';

    gemConfig = defaultGemConfig // {
      nokogiri = attrs: {
        buildInputs = [ pkg-config zlib.dev ];
      };
      mimemagic = attrs: {
        FREEDESKTOP_MIME_TYPES_PATH = "${shared-mime-info}/share/mime/packages/freedesktop.org.xml";
      };
      rmagick = attrs: {
        buildInputs = [ pkg-config imagemagick7' ];
      };
    };
  };
in stdenv.mkDerivation rec {
  name = "qbot";

  src = builtins.filterSource
    (path: type:
      type != "directory" ||
      baseNameOf path != "vendor" &&
      baseNameOf path != ".git" &&
      baseNameOf path != ".bundle")
    ./.;

  buildInputs = [
    env bundix' git
    sqlite libxml2 zlib.dev zlib libiconv
    libopus libsodium ffmpeg youtube-dl
    imagemagick7'
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [ libsodium libopus ];
  FONTCONFIG_FILE = "${src}/lib/resources/tokipona/fc-config.xml";

  installPhase = ''
    mkdir -p $out/{bin,share/qbot}
    cp -r * $out/share/qbot
    bin=$out/bin/qbot

    cat >$bin <<EOF
#!/bin/sh -e
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
export FONTCONFIG_FILE=${FONTCONFIG_FILE}
cd $out/share/qbot
exec ${env}/bin/bundle exec ${env.wrappedRuby}/bin/ruby $out/share/qbot/qbot "\$@"
EOF

    chmod +x $bin
  '';
}
