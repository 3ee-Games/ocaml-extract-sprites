open Cmdliner
open Bigarray
open ImageLib_unix

module P = Image.Pixmap

type bbox = { mutable min_x: int; mutable min_y: int; mutable max_x: int; mutable max_y: int }

let find parent label =
  let rec loop l =
    if parent.(l) < 0 then l else
      let p = loop parent.(l) in
      parent.(l) <- p;
      p
  in
  loop label

let union parent rank l1 l2 =
  let p1 = find parent l1 in
  let p2 = find parent l2 in
  if p1 <> p2 then
    if rank.(p1) > rank.(p2) then parent.(p2) <- p1
    else if rank.(p1) < rank.(p2) then parent.(p1) <- p2
    else (parent.(p2) <- p1; rank.(p1) <- rank.(p1) + 1)

let extract_sprites input output_dir prefix min_area alpha_threshold =
  if not (Sys.file_exists output_dir) then Unix.mkdir output_dir 0o755;
  let img = openfile input in
  let width = img.Image.width in
  let height = img.Image.height in
  let pixels = img.Image.pixels in
  let alpha_map =
    match pixels with
    | Image.RGBA (_, _, _, a) -> a
    | _ -> failwith "Only RGBA images supported"
  in
  let is_foreground x y = P.get alpha_map x y >= alpha_threshold in

  let labels = Array2.create int32 c_layout width height in
  Array2.fill labels 0l;

  let max_labels = width * height + 1 in
  let parent = Array.make max_labels (-1) in
  let rank = Array.make max_labels 0 in
  let next_label = ref 1 in

  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      if is_foreground x y then begin
        let linked = ref 0 in
        let check nx ny =
          let n = Array2.get labels nx ny in
          if n <> 0l then
            let r = find parent (Int32.to_int n) in
            if !linked = 0 then linked := r else if r <> !linked then union parent rank !linked r
        in
        if y > 0 then check x (y - 1);
        if x > 0 then check (x - 1) y;
        if y > 0 && x > 0 then check (x - 1) (y - 1);
        if y > 0 && x < width - 1 then check (x + 1) (y - 1);
        let this_label =
          if !linked = 0 then
            let l = !next_label in
            incr next_label; l
          else
            !linked
        in
        Array2.set labels x y (Int32.of_int this_label)
      end
    done
  done;

  let bboxes : (int, bbox) Hashtbl.t = Hashtbl.create 64 in
  let areas : (int, int) Hashtbl.t = Hashtbl.create 64 in

  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let pl = Array2.get labels x y in
      if pl <> 0l then begin
        let root = find parent (Int32.to_int pl) in
        let bb =
          match Hashtbl.find_opt bboxes root with
          | Some bb -> bb
          | None ->
              let nb = { min_x = x; min_y = y; max_x = x; max_y = y } in
              Hashtbl.add bboxes root nb; nb
        in
        bb.min_x <- min bb.min_x x;
        bb.min_y <- min bb.min_y y;
        bb.max_x <- max bb.max_x x;
        bb.max_y <- max bb.max_y y;
        let old = match Hashtbl.find_opt areas root with Some v -> v | None -> 0 in
        Hashtbl.replace areas root (old + 1)
      end
    done
  done;

  let components =
    Hashtbl.fold
      (fun root bb acc ->
        let area = match Hashtbl.find_opt areas root with Some v -> v | None -> 0 in
        if area >= min_area then (root, bb, area) :: acc else acc)
      bboxes
      []
    |> List.sort (fun (_, b1, _) (_, b2, _) ->
           if b1.min_y <> b2.min_y then compare b1.min_y b2.min_y
           else compare b1.min_x b2.min_x)
  in

  List.iteri
    (fun i (_, bb, _) ->
      let w = bb.max_x - bb.min_x + 1 in
      let h = bb.max_y - bb.min_y + 1 in
      let new_img = Image.create_rgb ~alpha:true ~max_val:255 w h in
      for ny = 0 to h - 1 do
        for nx = 0 to w - 1 do
          let ox = bb.min_x + nx in
          let oy = bb.min_y + ny in
          Image.read_rgba img ox oy (Image.write_rgba new_img nx ny)
        done
      done;
      let fname = Filename.concat output_dir (Printf.sprintf "%s%d.png" prefix (i + 1)) in
      writefile fname new_img)
    components

let input_arg =
  Arg.required
  @@ Arg.pos 0 (Arg.some Arg.file) None
  @@ Arg.info ~doc:"Input sprite sheet (PNG with alpha recommended)" []

let output_dir_arg =
  Arg.value
  @@ Arg.opt Arg.string "frames"
  @@ Arg.info [ "o"; "output-dir" ] ~doc:"Directory to write extracted sprites"

let prefix_arg =
  Arg.value
  @@ Arg.opt Arg.string "frame_"
  @@ Arg.info [ "p"; "prefix" ] ~doc:"Filename prefix for output frames"

let min_area_arg =
  Arg.value
  @@ Arg.opt Arg.int 64
  @@ Arg.info [ "m"; "min-area" ] ~doc:"Minimum connected component area (in pixels)"

let alpha_thresh_arg =
  Arg.value
  @@ Arg.opt Arg.int 1
  @@ Arg.info [ "t"; "alpha-threshold" ] ~doc:"Alpha threshold (0–255) for foreground detection"

let cmd =
  Term.(
    const extract_sprites
    $ input_arg
    $ output_dir_arg
    $ prefix_arg
    $ min_area_arg
    $ alpha_thresh_arg)

let info =
  Cmd.info "sprite_extract"
    ~doc:"Extract sprites from a sheet via connected-components with area filtering and alpha thresholding"

let () = exit @@ Cmd.eval (Cmd.v info cmd)
