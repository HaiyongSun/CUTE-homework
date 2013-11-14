open Types 
open OcamlSTP
  

let width = 64 

module Stp = OcamlSTP;;
   
(*
let opOfBop = function
  | Plus -> Stp.bv_add 
  | Minus -> Stp.bv_sub 
  | Mult -> Stp.bv_mult
  
let opOfRop = function
  | LT -> Stp.bv_signed_lt
  | LE -> Stp.bv_signed_le
  | GT -> Stp.bv_signed_gt
  | GE -> Stp.bv_signed_ge
  | EQ -> Stp.bv_signed_eq
  | NEQ -> (fun ctx x y -> Stp.bool_not ctx (Stp.bv_signed_eq ctx x y))

let rec bvOfSymExpr = function
    Symvar id -> 
    Stp.bv_var ctx id width
  | Symop of (bop, symExpr1, symExpr2) ->
    let v1 = bvOfSymExpr symExpr1 in
    let v2 = bvOfSymExpr symExpr2 in
      opOfBop bop ctx v1 v2 
  | Concrete i ->
    Stp.bv_of_int ctx width i 
    
let solveConstraints cnstr = 
  let cf = List.fold_left (* conjuctive form of the constraints *)
      (fun acc (Predicate (rop, symExpr1, symExpr2)) ->
        let v1 = bvOfSymExpr symExpr1 in
        let v2 = bvOfSymExpr symExpr2 in
        let c = opOfRop rop ctx v1 v2 in
         Stp.bool_and ctx c acc
      ) (Stp.bool_true ctx) cnstr
*)


(* Holds (address, expr) *)
let env = Hashtbl.create 101

let path_cnt = ref 0

let sym_vars = ref []

let add_symVar s = sym_vars := s :: (!sym_vars)

let execute_symbolic instr_node =
  match instr_node.instr with
    | Assign ((_, _), Lvalue (0, _)) -> ()
    | Assign ((m1, _), Lvalue (m2, _)) ->
        (match (try Some (Hashtbl.find env m2) with Not_found -> None) with 
          | Some v -> Hashtbl.add env m1 v
          | None -> Hashtbl.remove env m1)
    | Assign ((m1, _), Neg (0, _)) -> ()
    | Assign ((m1, _), Neg (m2, _)) -> ()
        (match (try Some (Hashtbl.find env m2) with Not_found -> None) with 
          | Some v -> Hashtbl.add env m1 (Symneg v)
          | None -> Hashtbl.remove env m1)
    | Assign ((m1, _), Bop (bop, (m2, vopt2), (m3, vopt3))) when bop = Mult ->
        (match (try Some (Hashtbl.find env m2) with Not_found -> None,
                try Some (Hashtbl.find env m3) with Not_found -> None) with 
           | Some v2, Some v3 -> 
               (match vopt2, vopt3 with
                  | Some cv2, _ -> 
                      Hashtbl.add env m1 (Symop (bop, Concrete cv2, v3)) 
                  | _, Some cv3 -> 
                      Hashtbl.add env m1 (Symop (bop, v2, Concrete cv3))
                  | _ -> failwith "Cannot proceed with no concrete value") 
           | Some v2, None ->
               let cv3 = match vopt3 with 
                   Some v -> Concrete v
                 | None -> failwith "Cannot proceed with no concrete value"
               in 
                 Hashtbl.add env m1 (Symop (bop, v2, cv3))
           | None, Some v3 ->
               let cv2 = match vopt2 with 
                   Some v -> Concrete v
                 | None -> failwith "Cannot proceed with no concrete value"
               in 
                 Hashtbl.add env m1 (Symop (bop, cv2, v3))
           | None, None -> Hashtbl.remove env m1)
    | Assign ((m1, _), Bop (bop, (m2, vopt2), (m3, vopt3))) ->
        (match (try Some (Hashtbl.find env m2) with Not_found -> None,
                try Some (Hashtbl.find env m3) with Not_found -> None) with 
           | Some v2, Some v3 -> 
               Hashtbl.add env m1 (Symop (bop, v2, v3))
           | Some v2, None ->
               let cv3 = match vopt3 with 
                   Some v -> Concrete v
                 | None -> failwith "Cannot proceed with no concrete value"
               in 
                 Hashtbl.add env m1 (Symop (bop, v2, cv3))
           | None, Some v3 ->
               let cv2 = match vopt2 with 
                   Some v -> Concrete v
                 | None -> failwith "Cannot proceed with no concrete value"
               in 
                 Hashtbl.add env m1 (Symop (bop, cv2, v3))
           | None, None -> Hashtbl.remove env m1)
   | Assign ((m1, _), Symbvalue (ty, symvar)) ->
         Hashtbl.add env m1 (Symvar symvar);
         add_symVar (symvar, ty)
   | Branch (taken, id, Cond (rop, ((m1, cv1), (m2, cv2)))) ->
       let rop = if taken then rop else Constraints.negateRop rop in
       let pred = 
         (match (try Some (Hashtbl.find env m1) with Not_found -> None,
                 try Some (Hashtbl.find env m2) with Not_found -> None) with
           | Some v1, Some v2 ->
               Predicate (rop, Symop (Minus, v1 v2), Concrete 0)
           | Some v1, None ->
               let v2 = match cv2 with 
                 | Some v -> Concrete v
                 | None -> failwith "Cannot proceed with no concrete value"
               in
               Predicate (rop, Symop (Minus, v1 v2), Concrete 0)
           | None, Some v2 ->
               let v2 = match cv2 with 
                 | Some v -> Concrete v
                 | None -> failwith "Cannot proceed with no concrete value"
               in
               Predicate (rop, Symop (Minus, v1 v2), Concrete 0)
           | None, None ->
               Constant taken)
       in
         Constraints.addPathConstraint !path_cnt pred;
         Constraints.compare_and_update_stack id taken !path_cnt
         incr path_cnt



