[@@@ocaml.warning "+a-30-40-41-42"]

open! Int_replace_polymorphic_compare
open! Regalloc_utils
open! Regalloc_gi_utils
module State = Regalloc_gi_state
module Utils = Regalloc_gi_utils

let rewrite : State.t -> Cfg_with_infos.t -> spilled_nodes:Reg.t list -> bool =
 fun state cfg_with_infos ~spilled_nodes ->
  let new_inst_temporaries, new_block_temporaries, block_inserted =
    Regalloc_rewrite.rewrite_gen
      (module State)
      (module Utils)
      state cfg_with_infos ~spilled_nodes ~block_temporaries:false
  in
  assert (Misc.Stdlib.List.is_empty new_block_temporaries);
  if not (Misc.Stdlib.List.is_empty new_inst_temporaries)
  then Cfg_with_infos.invalidate_liveness cfg_with_infos;
  if block_inserted
  then Cfg_with_infos.invalidate_dominators_and_loop_infos cfg_with_infos;
  match new_inst_temporaries with
  | [] -> false
  | _ :: _ ->
    State.add_introduced_temporaries_list state new_inst_temporaries;
    State.clear_assignments state;
    true

let update_register_locations : State.t -> unit =
 fun state ->
  if debug
  then (
    log "update_register_locations";
    indent ());
  let update_register (reg : Reg.t) : unit =
    match reg.Reg.loc with
    | Reg _ -> ()
    | Stack _ -> ()
    | Unknown -> (
      match State.find_assignment state reg with
      | None ->
        (* a register may "disappear" because of split/rename *)
        ()
      | Some location ->
        if debug
        then
          log "updating %a to %a" Printreg.reg reg
            Hardware_register.print_location location;
        reg.Reg.loc <- Hardware_register.reg_location_of_location location)
  in
  List.iter (Reg.all_relocatable_regs ()) ~f:update_register;
  if debug then dedent ()

module Prio_queue = Priority_queue.Make (Int)

type prio_queue = (Reg.t * Interval.t) Prio_queue.t

let priority_heuristics : Reg.t -> Interval.t -> int =
 fun _reg itv ->
  match Lazy.force Priority_heuristics.value with
  | Priority_heuristics.Interval_length -> Interval.length itv
  | Priority_heuristics.Random_for_testing -> Priority_heuristics.random ()

let make_hardware_registers_and_prio_queue (cfg_with_infos : Cfg_with_infos.t) :
    Hardware_registers.t * prio_queue =
  if debug
  then (
    log "creating registers and queue";
    indent ());
  let intervals = build_intervals cfg_with_infos in
  let hardware_registers = Hardware_registers.make () in
  let prio_queue =
    (* CR-soon xclerc for xclerc: use the number of temporaries. *)
    Prio_queue.make ~initial_capacity:256
  in
  Reg.Tbl.iter
    (fun reg interval ->
      match reg.loc with
      | Reg _ -> (
        if debug
        then (
          log "pre-assigned register %a" Printreg.reg reg;
          indent ();
          log "%a" Interval.print interval;
          dedent ());
        match Hardware_registers.of_reg hardware_registers reg with
        | None -> ()
        | Some hardware_reg ->
          Hardware_register.add_non_evictable hardware_reg reg interval)
      | Unknown ->
        let priority = priority_heuristics reg interval in
        if debug
        then (
          log "register %a" Printreg.reg reg;
          indent ();
          log "%a" Interval.print interval;
          log "priority=%d" priority;
          dedent ());
        Prio_queue.add prio_queue ~priority ~data:(reg, interval)
      | Stack _ ->
        if debug
        then (
          log "stack register %a" Printreg.reg reg;
          indent ();
          log "%a" Interval.print interval;
          dedent ());
        ())
    intervals;
  if debug then dedent ();
  hardware_registers, prio_queue

(* CR xclerc for xclerc: try to find a reasonable threshold. *)
let max_rounds = 32

let max_temp_multiplier = 10

module For_testing = struct
  let rounds = ref (-1)
end

(* CR xclerc for xclerc: the `round` parameter is temporary; this is an hybrid
   version of "greedy" using the `rewrite` function from IRC when it needs to
   spill. *)
let rec main : round:int -> flat:bool -> State.t -> Cfg_with_infos.t -> unit =
 fun ~round ~flat state cfg_with_infos ->
  For_testing.rounds := round;
  if round > max_rounds
  then
    fatal "register allocation was not succesful after %d rounds (%s)"
      max_rounds (Cfg_with_infos.cfg cfg_with_infos).fun_name;
  if State.introduced_temporary_count state
     > State.initial_temporary_count state * max_temp_multiplier
  then
    fatal "register allocation introduced %d temporaries after starting with %d"
      (State.introduced_temporary_count state)
      (State.initial_temporary_count state);
  if debug
  then (
    log "main, round #%d" round;
    log_cfg_with_infos cfg_with_infos);
  if debug then log "updating spilling costs";
  let costs = SpillCosts.compute cfg_with_infos ~flat () in
  State.iter_introduced_temporaries state ~f:(fun (reg : Reg.t) ->
      SpillCosts.add_to_reg costs reg 10_000);
  if debug
  then (
    log "spilling costs";
    indent ();
    SpillCosts.iter costs ~f:(fun (reg : Reg.t) (cost : int) ->
        log "%a: %d" Printreg.reg reg cost);
    dedent ());
  let hardware_registers, prio_queue =
    make_hardware_registers_and_prio_queue cfg_with_infos
  in
  let step = ref 0 in
  let spilling = ref ([] : (Reg.t * Interval.t) list) in
  indent ();
  while not (Prio_queue.is_empty prio_queue) do
    incr step;
    if debug then log "step #%d (size=%d)" !step (Prio_queue.size prio_queue);
    let { Prio_queue.priority; data = reg, interval } =
      Prio_queue.get_and_remove prio_queue
    in
    if debug
    then (
      indent ();
      log "got register %a (prio=%d)" Printreg.reg reg priority);
    (match
       Hardware_registers.find_available hardware_registers costs reg interval
     with
    | For_assignment { hardware_reg } ->
      if debug
      then
        log "assigning %a to %a" Printreg.reg reg
          Hardware_register.print_location hardware_reg.location;
      State.add_assignment state reg ~to_:hardware_reg.location;
      hardware_reg.assigned
        <- { Hardware_register.pseudo_reg = reg; interval; evictable = true }
           :: hardware_reg.assigned
    | For_eviction { hardware_reg; evicted_regs } ->
      if debug
      then
        log "evicting %a from %a" Printreg.regs
          (Array.of_list
             (List.map evicted_regs
                ~f:(fun { Hardware_register.pseudo_reg; _ } -> pseudo_reg)))
          Hardware_register.print_location hardware_reg.location;
      List.iter evicted_regs
        ~f:(fun
             { Hardware_register.pseudo_reg = evict_reg;
               interval = evict_interval;
               evictable
             }
           ->
          if not evictable
          then
            fatal
              "register %a has been picked up for eviction, but is not \
               evictable"
              Printreg.reg evict_reg;
          State.remove_assignment state evict_reg;
          Prio_queue.add prio_queue
            ~priority:(priority_heuristics evict_reg evict_interval)
            ~data:(evict_reg, evict_interval));
      State.add_assignment state reg ~to_:hardware_reg.location;
      (* CR xclerc for xclerc: very inefficient. *)
      hardware_reg.assigned
        <- { Hardware_register.pseudo_reg = reg; interval; evictable = true }
           :: List.filter hardware_reg.assigned
                ~f:(fun { Hardware_register.pseudo_reg = r; _ } ->
                  not
                    (List.exists evicted_regs
                       ~f:(fun { Hardware_register.pseudo_reg = r'; _ } ->
                         Reg.same r r')))
    | Split_or_spill ->
      (* CR xclerc for xclerc: we should actually try to split. *)
      if debug then log "spilling %a" Printreg.reg reg;
      spilling := (reg, interval) :: !spilling);
    if debug then dedent ()
  done;
  dedent ();
  match !spilling with
  | [] -> ()
  | _ :: _ as spilled_nodes -> (
    if debug
    then (
      log_cfg_with_infos cfg_with_infos;
      indent ();
      log "stack slots";
      indent ();
      Regalloc_stack_slots.iter (State.stack_slots state)
        ~f:(fun (reg : Reg.t) (slot : int) ->
          log "  - %a ~> %d" Printreg.reg reg slot);
      dedent ();
      log "needs to spill %d registers:" (List.length !spilling);
      indent ();
      List.iter !spilling ~f:(fun (_reg, interval) ->
          log "  - %a" Interval.print interval);
      dedent ();
      dedent ();
      Cfg.iter_blocks (Cfg_with_infos.cfg cfg_with_infos)
        ~f:(fun (_ : Label.t) (block : Cfg.basic_block) ->
          let occurs =
            List.exists spilled_nodes ~f:(fun (reg, _) ->
                occurs_block block reg)
          in
          if occurs
          then (
            let dummy_liveness_for_log = InstructionId.Tbl.create 12 in
            log "block %a has an occurrence of a spilling register" Label.format
              block.start;
            indent ();
            log_body_and_terminator block.body block.terminator
              dummy_liveness_for_log;
            dedent ())));
    match
      rewrite state cfg_with_infos
        ~spilled_nodes:(List.map spilled_nodes ~f:fst)
    with
    | false -> if debug then log "(end of main)"
    | true -> main ~round:(succ round) ~flat state cfg_with_infos)

let run : Cfg_with_infos.t -> Cfg_with_infos.t =
 fun cfg_with_infos ->
  if debug then reset_indentation ();
  let cfg_with_layout = Cfg_with_infos.cfg_with_layout cfg_with_infos in
  let cfg_infos, stack_slots =
    Regalloc_rewrite.prelude
      (module Utils)
      ~on_fatal_callback:(fun () -> save_cfg "gi" cfg_with_layout)
      cfg_with_infos
  in
  (* CR xclerc for xclerc: consider moving the computation of temporaries and
     the creation of the state to `prelude`. *)
  let all_temporaries = Reg.Set.union cfg_infos.arg cfg_infos.res in
  let initial_temporaries = Reg.Set.cardinal all_temporaries in
  if debug then log "#temporaries=%d" initial_temporaries;
  let state = State.make ~stack_slots ~initial_temporaries in
  let spilling_because_unused = Reg.Set.diff cfg_infos.res cfg_infos.arg in
  (match Reg.Set.elements spilling_because_unused with
  | [] -> ()
  | _ :: _ as spilled_nodes ->
    (* note: rewrite will remove the `spilling` registers from the "spilled"
       work list and set the field to unknown. *)
    let (_ : bool) = rewrite state cfg_with_infos ~spilled_nodes in
    Cfg_with_infos.invalidate_liveness cfg_with_infos);
  let flat =
    match Lazy.force Spilling_heuristics.value with
    | Flat_uses -> true
    | Hierarchical_uses -> false
    | Random_for_testing -> Spilling_heuristics.random ()
  in
  main ~round:1 ~flat state cfg_with_infos;
  if debug
  then (
    indent ();
    log_cfg_with_infos cfg_with_infos;
    dedent ());
  Regalloc_rewrite.postlude
    (module State)
    (module Utils)
    state
    ~f:(fun () -> update_register_locations state)
    cfg_with_infos;
  cfg_with_infos
