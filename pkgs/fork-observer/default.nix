{ stdenv, pkgs, lib, rustPlatform, ... }:

rustPlatform.buildRustPackage rec {
  pname = "fork-observer";
  name = "fork-observer";
  version = "bcd93a42083ac1ce96b744e2a91a268a4efa7e07";

  src = pkgs.fetchFromGitHub {
    owner = "0xB10C";
    repo = "fork-observer";
    rev = version;
    sha256 = "sha256-Vi12bZ3P4dHGjF/JnSy97SK9zutr52jR4N7Yx4QloLQ=";
  };

  nativeBuildInputs = with pkgs; [ sqlite ];

  cargoHash = "sha256-Zc/thU1KnjMUdAjB11rRbd3EQU13kZ2Ly6BRD6GSDmw=";

  postInstall = ''
    cp -r www $out/www
  '';

  meta = with stdenv.lib; {
    description = "Tool for monitoring forks and reorgs on Bitcoin networks.";
    longDescription = ''
      The fork-observer can be hooked up to one or more Bitcoin Core nodes via
      the RPC interface. It gathers and visualizes data on block headers, forks
      in the chain, and stale blocks. It supports multiple networks (mainnet,
      testnet, (custom) signets, ...).
    '';
    homepage = "https://github.com/0xb10c/fork-observer";
    license = lib.licenses.mit;
  };
}
