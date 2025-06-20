open import Haskell.Prelude
  hiding ( All; m; _,_,_)
  renaming (_,_ to infixr 5 _,_)
open import Haskell.Extra.Dec
open import Haskell.Extra.Erase
open import Haskell.Law.Equality renaming (subst to transport)

open import Agda.Core.Name
open import Agda.Core.Utils
open import Agda.Core.Syntax
open import Agda.Core.Conversion
open import Agda.Core.Typing
open import Agda.Core.Reduce
open import Agda.Core.TCM
open import Agda.Core.TCMInstances
open import Agda.Core.Converter

module Agda.Core.Typechecker
    {{@0 globals : Globals}}
    {{@0 sig     : Signature}}
  where

private open module @0 G = Globals globals

private variable
  @0 x : Name
  @0 α : Scope Name
  @0 rβ : RScope Name

checkCoerce : ∀ Γ (t : Term α)
            → Σ[ ty ∈ Type α ] Γ ⊢ t ∶ ty
            → (cty : Type α)
            → TCM (Γ ⊢ t ∶ cty)
checkCoerce ctx t (gty , dgty) cty = do
  let r = rezzScope ctx
  TyConv dgty <$> convert r (unType gty) (unType cty)
{-# COMPILE AGDA2HS checkCoerce #-}

tcmGetType : (x : NameIn defScope) → TCM (Rezz (getType {α = α} sig x))
tcmGetType x = do
  rsig ← tcmSignature
  return (rezzCong (λ sig → getType sig x) rsig)
{-# COMPILE AGDA2HS tcmGetType #-}

tcmGetDefinition : (x : NameIn defScope) → TCM (Rezz (getDefinition sig x))
tcmGetDefinition x = do
  rsig ← tcmSignature
  return (rezzCong (λ sig → getDefinition sig x) rsig)
{-# COMPILE AGDA2HS tcmGetDefinition #-}

tcmGetDatatype : (d : NameData) → TCM (Rezz (sigData sig d))
tcmGetDatatype d = do
  rsig ← tcmSignature
  return (rezzCong (λ sig → sigData sig d) rsig)
{-# COMPILE AGDA2HS tcmGetDatatype #-}

tcmGetConstructor : {d : NameData} (c : NameCon d) → TCM (Rezz (sigCons sig d c))
tcmGetConstructor {d = d} c = do
  rsig ← tcmSignature
  return (rezzCong (λ sig → sigCons sig d c) rsig)
{-# COMPILE AGDA2HS tcmGetConstructor #-}

inferVar : ∀ Γ (x : NameIn α) → TCM (Σ[ t ∈ Type α ] Γ ⊢ TVar x ∶ t)
inferVar ctx x = return $ _ , TyTVar
{-# COMPILE AGDA2HS inferVar #-}

inferSort : (Γ : Context α) (t : Term α) → TCM (Σ[ s ∈ Sort α ] Γ ⊢ t ∶ sortType s)
inferType : ∀ (Γ : Context α) u → TCM (Σ[ t ∈ Type α ] Γ ⊢ u ∶ t)
checkType : ∀ (Γ : Context α) u (ty : Type α) → TCM (Γ ⊢ u ∶ ty)
checkBranches : ∀ {d : NameData} {@0 cons : RScope (NameCon d)}
                  (Γ : Context α)
                  (rz : Rezz cons)
                  (bs : Branches α d cons)
                  (dt : Datatype d)
                  (ps : TermS α (dataParScope d))
                  (rt : Type (extScope α (dataIxScope d) ▸ x))
                → TCM (TyBranches Γ dt ps rt bs)

inferApp : ∀ Γ u v → TCM (Σ[ t ∈ Type α ] Γ ⊢ TApp u v ∶ t)
inferApp ctx u v = do
  let r = rezzScope ctx
  tu , gtu ← inferType ctx u
  ⟨ x ⟩ (at , rt) ⟨ rtp ⟩ ← reduceToPi r (unType tu)
    "couldn't reduce term to a pi type"
  gtv ← checkType ctx v at
  let tytype = substTop r v rt
      gc = CRedL rtp CRefl
      gtu' =  TyConv {b = El (typeSort tu) (TPi x at rt)} gtu gc
  return (tytype , TyApp gtu' gtv)
{-# COMPILE AGDA2HS inferApp #-}

inferCase : ∀ Γ d r u bs rt → TCM (Σ[ t ∈ Type α ] Γ ⊢ TCase {x = x} d r u bs rt ∶ t)
inferCase {α = α} ctx d rixs u bs rt = do
  let r = rezzScope ctx

  El s tu , gtu ← inferType ctx u
  d' , (params , ixs) ⟨ rp ⟩ ← reduceToData r tu
    "can't typecheck a constrctor with a type that isn't a def application"
  Erased refl ← convNamesIn d d'
  df ⟨ deq ⟩ ← tcmGetDatatype d
  let ds : Sort α
      ds = instDataSort df params
      gtu' : ctx ⊢ u ∶ dataType d ds params ixs
      gtu' = TyConv gtu (CRedL rp CRefl)

  grt ← checkType (_ , _ ∶ weaken (subExtScope rixs subRefl) (dataType d ds params ixs)) (unType rt) (sortType (typeSort rt))

  -- Erased refl ← checkCoverage df bs
  cb ← checkBranches ctx (rezzBranches bs) bs df params rt

  return (_ , tyCase' {k = ds} df deq {iRun = rixs} grt cb gtu')

{-# COMPILE AGDA2HS inferCase #-}

inferPi
  : ∀ Γ (@0 x : Name)
  (a : Type α)
  (b : Type  (α ▸ x))
  → TCM (Σ[ ty ∈ Type α ] Γ ⊢ TPi x a b ∶ ty)
inferPi ctx x (El su u) (El sv v) = do
  tu <- checkType ctx u (sortType su)
  tv <- checkType (ctx , x ∶ El su u) v (sortType sv)
  let spi = piSort su sv
  return $ sortType spi , TyPi tu tv
{-# COMPILE AGDA2HS inferPi #-}

inferTySort : ∀ Γ (s : Sort α) → TCM (Σ[ ty ∈ Type α ] Γ ⊢ TSort s ∶ ty)
inferTySort ctx (STyp x) = return $ sortType (sucSort (STyp x)) , TyType
{-# COMPILE AGDA2HS inferTySort #-}

inferDef : ∀ Γ (f : NameIn defScope)
         → TCM (Σ[ ty ∈ Type α ] Γ ⊢ TDef f ∶ ty)
inferDef ctx f = do
  ty ⟨ eq ⟩ ← tcmGetType f
  return $ ty , tyDef' ty eq
{-# COMPILE AGDA2HS inferDef #-}

checkTermS : ∀ {@0 α rβ} Γ (t : Telescope α rβ) (s : TermS α rβ) → TCM (Γ ⊢ˢ s ∶ t)
checkTermS ctx ⌈⌉ t =
  caseTermSNil t (λ where ⦃ refl ⦄ → return TyNil)
checkTermS {α = α} ctx (ExtendTel {rβ = rβ} x ty rest) ts =
  caseTermSCons ts (λ where
    u s ⦃ refl ⦄ → do
      tyx ← checkType ctx u ty
      let r = rezzScope ctx
          stel : Telescope α rβ
          stel = substTelescope (idSubst r ▹ x ↦ u) rest
      tyrest ← checkTermS ctx stel s
      return (TyCons tyx tyrest))
{-# COMPILE AGDA2HS checkTermS #-}

inferData : (Γ : Context α) (d : NameData)
          → (pars : TermS α (dataParScope d)) (ixs : TermS α (dataIxScope d))
          → TCM (Σ[ ty ∈ Type α ] Γ ⊢ TData d pars ixs ∶ ty)
inferData ctx d pars ixs = do
  dt ⟨ deq ⟩ ← tcmGetDatatype d
  typars ← checkTermS ctx (instDataParTel dt) pars
  tyixs ← checkTermS ctx (instDataIxTel dt pars) ixs
  return (sortType (instDataSort dt pars) , tyData' dt deq typars tyixs)
{-# COMPILE AGDA2HS inferData #-}

checkBranch : ∀ {d : NameData} {@0 con : NameCon d} (Γ : Context α)
                (bs : Branch α con)
                (dt : Datatype d)
                (ps : TermS α (dataParScope d))
                (rt : Type (extScope α (dataIxScope d) ▸ x))
            → TCM (TyBranch Γ dt ps rt bs)
checkBranch {α = α} {d = d} ctx (BBranch (rezz c) r rhs) dt ps rt = do
  -- cid ⟨ refl ⟩  ← liftMaybe (getConstructor c dt)
    -- "can't find a constructor with such a name"
  con ⟨ ceq ⟩ ← tcmGetConstructor c
  let ra = rezzScope ctx
      @0 β : Scope Name
      β = extScope α (fieldScope c)
      cargs : TermS β (fieldScope c)
      cargs = termSrepeat r
      parssubst : TermS β (dataParScope d)
      parssubst = weaken (subExtScope r subRefl) ps
      ixsubst : TermS β (dataIxScope d)
      ixsubst = instConIx con parssubst cargs
      idsubst : α ⇒ β
      idsubst = weaken (subExtScope r subRefl) (idSubst ra)
      bsubst : extScope α (dataIxScope d) ▸ x ⇒ β
      bsubst = extSubst idsubst ixsubst ▹ _ ↦ TCon c cargs
      rt' :  Type β
      rt' = subst bsubst rt
  crhs ← checkType _ rhs rt'
  return (tyBBranch' c con ceq {r = r} rhs crhs)
{-# COMPILE AGDA2HS checkBranch #-}

checkBranches {d = d} ctx (rezz cons) bs dt ps rt =
  caseRScope cons
    (λ where {{refl}} → caseBsNil bs (λ where {{refl}} → return TyBsNil))
    (λ ch ct → λ where
      {{refl}} → caseBsCons bs (λ bh bt → λ where
        {{refl}} → TyBsCons <$> checkBranch {d = d} ctx bh dt ps rt
                            <*> checkBranches ctx (rezzBranches bt) bt dt ps rt))
{-# COMPILE AGDA2HS checkBranches #-}

checkCon : ∀ Γ
           {d : NameData}
           (c : NameCon d)
           (cargs : TermS α (fieldScope c))
           (ty : Type α)
         → TCM (Γ ⊢ TCon c cargs ∶ ty)
checkCon ctx {d = d} c cargs (El s ty) = do
  let r = rezzScope ctx
  d' , (params , ixs) ⟨ rp ⟩ ← reduceToData r ty
    "can't typecheck a constructor with a type that isn't a def application"
  ifDec (decIn (proj₂ d) (proj₂ d'))
    (λ where {{refl}} → do
        dt ⟨ dteq ⟩ ← tcmGetDatatype d
        -- cid ⟨ refl ⟩  ← liftMaybe (getConstructor c dt)
          -- "can't find a constructor with such a name"
        con ⟨ ceq ⟩ ← tcmGetConstructor c
        let ctel = instConIndTel con params
            ctype = constructorType dt con params cargs
        tySubst ← checkTermS ctx ctel cargs
        checkCoerce ctx (TCon c cargs) (ctype , tyCon' dt dteq con ceq tySubst) (El s ty))
    (tcError "datatypes not convertible")

{-# COMPILE AGDA2HS checkCon #-}

checkLambda : ∀ Γ (@0 x : Name)
              (u : Term  (α ▸ x))
              (ty : Type α)
              → TCM (Γ ⊢ TLam x u ∶ ty)
checkLambda ctx x u (El s ty) = do
  let r = rezzScope ctx

  ⟨ y ⟩ (tu , tv) ⟨ rtp ⟩ ← reduceToPi r ty
    "couldn't reduce a term to a pi type"
  let gc = CRedR rtp (CPi CRefl CRefl)
      sp = piSort (typeSort tu) (typeSort tv)

  d ← checkType (ctx , x ∶ tu) u (renameTopType (rezzScope ctx) tv)

  return $ TyConv (TyLam {k = sp} d) gc

{-# COMPILE AGDA2HS checkLambda #-}

checkLet : ∀ Γ (@0 x : Name)
           (u : Term α)
           (v : Term  (α ▸ x))
           (ty : Type α)
           → TCM (Γ ⊢ TLet x u v ∶ ty)
checkLet ctx x u v ty = do
  tu , dtu  ← inferType ctx u
  dtv       ← checkType (ctx , x ∶ tu) v (weaken (subBindDrop subRefl) ty)
  return $ TyLet dtu dtv
{-# COMPILE AGDA2HS checkLet #-}


checkType ctx (TVar x) ty = do
  tvar ← inferVar ctx x
  checkCoerce ctx (TVar x) tvar ty
checkType ctx (TDef d) ty = do
  tdef ← inferDef ctx d
  checkCoerce ctx (TDef d) tdef ty
checkType ctx (TData d ps is) ty = do
  tdef ← inferData ctx d ps is
  checkCoerce ctx (TData d ps is) tdef ty
checkType ctx (TCon c x) ty = checkCon ctx c x ty
checkType ctx (TLam x te) ty = checkLambda ctx x te ty
checkType ctx (TApp u e) ty = do
  tapp ← inferApp ctx u e
  checkCoerce ctx (TApp u e) tapp ty
checkType ctx (TCase d r u bs rt) ty = do
  tapp ← inferCase ctx d r u bs rt
  checkCoerce ctx (TCase d r u bs rt) tapp ty
checkType ctx (TProj u f) ty = tcError "not implemented: projections"
checkType ctx (TPi x tu tv) ty = do
  tpi ← inferPi ctx x tu tv
  checkCoerce ctx (TPi x tu tv) tpi ty
checkType ctx (TSort s) ty = do
  tts ← inferTySort ctx s
  checkCoerce ctx (TSort s) tts ty
checkType ctx (TLet x u v) ty = checkLet ctx x u v ty
checkType ctx (TAnn u t) ty = do
  ct ← TyAnn <$> checkType ctx u t
  checkCoerce ctx (TAnn u t) (t , ct) ty

{-# COMPILE AGDA2HS checkType #-}

inferType ctx (TVar x) = inferVar ctx x
inferType ctx (TDef d) = inferDef ctx d
inferType ctx (TData d ps is) = inferData ctx d ps is
inferType ctx (TCon c x) = tcError "non inferrable: can't infer the type of a constructor"
inferType ctx (TLam x te) = tcError "non inferrable: can't infer the type of a lambda"
inferType ctx (TApp u e) = inferApp ctx u e
inferType ctx (TCase d r u bs rt) = inferCase ctx d r u bs rt
inferType ctx (TProj u f) = tcError "not implemented: projections"
inferType ctx (TPi x a b) = inferPi ctx x a b
inferType ctx (TSort s) = inferTySort ctx s
inferType ctx (TLet x te te₁) = tcError "non inferrable: can't infer the type of a let"
inferType ctx (TAnn u t) = (_,_) t <$> (TyAnn <$> checkType ctx u t)

{-# COMPILE AGDA2HS inferType #-}

inferSort ctx t = do
  let r = rezzScope ctx
  st , dt ← inferType ctx t
  s ⟨ rp ⟩ ← reduceToSort r (unType st) "couldn't reduce a term to a sort"
  let cp = CRedL rp CRefl
  return $ s , TyConv dt cp

{-# COMPILE AGDA2HS inferSort #-}
