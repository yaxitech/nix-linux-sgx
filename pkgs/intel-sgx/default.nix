{ pkgs ? import <nixpkgs> { }
, callPackage ? pkgs.callPackage
, debug ? false
, ...
}:
{
  repoPrepared = callPackage ./repo-prepared.nix { };
  sdk = callPackage ./sdk.nix { inherit debug; };
  psw = callPackage ./psw.nix { inherit debug; };
}
