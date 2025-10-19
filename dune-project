(lang dune 3.20)

(name extract_sprites)

(generate_opam_files true)

(source
 (github ryanootie/extract_sprites))

(authors "Ryan Sadwick <rsadwick@gmail.com>")

(maintainers "Ryan Sadwick <rsadwick@gmail.com>")

(license MIT)

(documentation https://github.com/ryanootie/extract_sprites#readme)

(package
 (name extract_sprites)
 (synopsis "A CLI tool to extract individual sprites from a spritesheet")
 (description
  "An OCaml command-line utility that loads an image, detects connected
   pixel regions, and exports them as cropped sprite PNGs. Built with
   ImageLib and Cmdliner for fast & dependency-light workflow.")
 (depends
  (ocaml (>= 5.0))
  dune
  cmdliner
  imagelib
  imagelib.unix)
 (tags
  ("ocaml" "imagelib" "sprites" "image-processing" "cli" "gamedev")))
