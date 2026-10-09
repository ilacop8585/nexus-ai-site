-- NEXUS Word Admin Center: SQL ambiguity repair, non-destructive.
-- No roles, ledger, credits or user rows modified by this migration.
-- Existing owner authorization, SECURITY DEFINER and signatures preserved.
CREATE OR REPLACE FUNCTION public.nexus_admin_set_beta(p_target uuid, p_enabled boolean)
RETURNS TABLE(user_id uuid, staff_role text, unlimited boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_admin uuid; v_role text; v_unlimited boolean;
BEGIN
  v_admin := (auth.user_id())::uuid;
  IF NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT sa.role,sa.unlimited_qa INTO v_role,v_unlimited
    FROM public.nexus_staff_accounts AS sa WHERE sa.user_id=p_target;
  IF v_role IN ('owner','admin') THEN RAISE EXCEPTION 'protected_staff_role'; END IF;
  IF coalesce(p_enabled,false) THEN
    INSERT INTO public.nexus_staff_accounts(user_id,role,unlimited_qa)
      VALUES(p_target,'beta_tester',true)
      ON CONFLICT ON CONSTRAINT nexus_staff_accounts_pkey
      DO UPDATE SET role='beta_tester',unlimited_qa=true;
    v_role:='beta_tester'; v_unlimited:=true;
  ELSIF v_role='beta_tester' THEN
    DELETE FROM public.nexus_staff_accounts AS sa WHERE sa.user_id=p_target;
    v_role:=NULL;v_unlimited:=false;
  END IF;
  INSERT INTO public.nexus_admin_audit(admin_user_id,target_user_id,action,details)
    VALUES(v_admin,p_target,'set_beta',jsonb_build_object('enabled',coalesce(p_enabled,false),'role',v_role,'unlimited',coalesce(v_unlimited,false)));
  RETURN QUERY SELECT p_target,v_role,coalesce(v_unlimited,false);
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_admin_set_unlimited(p_target uuid, p_unlimited boolean)
RETURNS TABLE(user_id uuid, staff_role text, unlimited boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_admin uuid;v_role text;
BEGIN
  v_admin := (auth.user_id())::uuid;
  IF NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT sa.role INTO v_role FROM public.nexus_staff_accounts AS sa WHERE sa.user_id=p_target;
  IF v_role='owner' AND NOT coalesce(p_unlimited,false) THEN RAISE EXCEPTION 'owner_must_remain_unlimited'; END IF;
  IF v_role IS NULL THEN
    IF coalesce(p_unlimited,false) THEN
      INSERT INTO public.nexus_staff_accounts(user_id,role,unlimited_qa) VALUES(p_target,'unlimited_user',true);
      v_role:='unlimited_user';
    ELSE
      RETURN QUERY SELECT p_target,NULL::text,false;
      RETURN;
    END IF;
  ELSE
    UPDATE public.nexus_staff_accounts AS sa SET unlimited_qa=coalesce(p_unlimited,false)
      WHERE sa.user_id=p_target;
  END IF;
  INSERT INTO public.nexus_admin_audit(admin_user_id,target_user_id,action,details)
    VALUES(v_admin,p_target,'set_unlimited',jsonb_build_object('enabled',coalesce(p_unlimited,false),'role',v_role));
  RETURN QUERY SELECT p_target,v_role,coalesce(p_unlimited,false);
END
$function$;