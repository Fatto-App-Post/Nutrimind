-- =====================================================================
-- NutriMind — 015 ALIMENTI PERSONALI E GESTIONE PASTI SALVATI
-- Rieseguibile.
-- 1. Il paziente può creare alimenti personali quando un prodotto non è
--    in catalogo. La policy foods_insert_user (003) impone già
--    source = 'user' e verification = 'unverified': qui si concede solo
--    INSERT sulle colonne che l'app compila.
-- 2. Il paziente può cancellare i propri pasti salvati.
-- =====================================================================

grant insert (
  name, brand, barcode,
  kcal, protein_g, carbs_g, fat_g,
  fiber_g, sugars_g, saturated_fat_g, salt_g,
  serving_g, serving_label,
  source, verification
) on public.foods to authenticated;

grant delete on public.personal_meals to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'foods' and cmd in ('INSERT', 'ALL')
      and 'authenticated' = any(roles)
  ) then
    create policy foods_insert_user on public.foods for insert to authenticated
    with check (source = 'user' and verification = 'unverified' and created_by = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'personal_meals' and cmd in ('DELETE', 'ALL')
  ) then
    create policy personal_meals_delete_own on public.personal_meals for delete to authenticated
    using (patient_id = auth.uid());
  end if;
end;
$$;
