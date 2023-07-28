type wasm_compilation_unit = string

let tmp_dirname = "wasocaml"

type tmp_file =
  { name : string
  ; filename : string
  }

let out_file (name, (wast : Wast.t)) =
  let filename, oc =
    Filename.open_temp_file (tmp_dirname ^ "/" ^ name) ".wast"
  in
  Format.printf "tmp_file: %s@." filename;
  let ppf = Format.formatter_of_out_channel oc in
  Misc.try_finally
    ~always:(fun () ->
      Format.fprintf ppf "@.";
      close_out oc )
    (fun () ->
        Emit_wast.output_wast ppf wast.module_;
        Format.fprintf ppf "@\n";
        Emit_wast.output_wast ppf wast.register );
  { name; filename }

let emit_text = "--emit-text"
let skip_export_conflicts = "--skip-export-conflicts"
let options =
  [ "--enable-multivalue"
  ; "--enable-gc"
  ; "--enable-reference-types"
  ; "--enable-exception-handling"
  ; "--enable-tail-call"
  ]

let wasm_merge = "wasm-merge"

let runtime =
  [ (Wstate.exc_tag_module, Wstate.exc_tag_module)
  ; (Wstate.runtime_module ^ "_binaryen", Wstate.runtime_module)
  ; (Wstate.imports_module ^ "_binaryen", Wstate.imports_module)
  ]

let merge_files ~runtime_dir ~text files output =
  let text = if text then [ emit_text ] else [] in
  let command =
    let runtime_files =
      List.concat_map
        (fun (file, name) -> [ Filename.concat runtime_dir (file ^ ".wast"); name ])
        runtime
    in
    let ocaml_files =
      List.concat_map (fun { name; filename } -> [ filename; name ]) files
    in
    Filename.quote_command wasm_merge
      ( options @ [ skip_export_conflicts ] @ text @ runtime_files @ ocaml_files
        @ [ "-o"; output ] )
  in
  Format.printf "%s@." command;
  let code = Sys.command command in
  if code <> 0 then begin Format.eprintf "wasm-merge failed@."
  (* failwith "Wasm link error" *)
  end

let rec make_directory dir =
  if Sys.file_exists dir then ()
  else begin
    make_directory (Filename.dirname dir);
    Sys.mkdir dir 0o777
  end

let link (modules : (wasm_compilation_unit * Wast.t) list) ~output =
  let output_wast = output ^ ".wast" in
  let output_wasm = output ^ ".wasm" in
  Format.eprintf "OUTPUT: %s@." output_wast;
  let dirname = Filename.concat (Filename.get_temp_dir_name ()) tmp_dirname in
  make_directory dirname;
  (* Sys.mkdir dirname 0o700; *)
  let tmp_modules = List.map out_file modules in
  let runtime_dir = Config.standard_library in
  merge_files ~runtime_dir ~text:true tmp_modules output_wast;
  merge_files ~runtime_dir ~text:false tmp_modules output_wasm
