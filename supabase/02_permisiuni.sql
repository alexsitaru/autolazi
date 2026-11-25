-- AutoLaZi – permisiuni (se rulează în SQL Editor, o singură dată; nu strică nimic dacă rulezi din nou)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.autolazi_data to authenticated;
grant select on public.app_subscriptions to authenticated;
grant execute on function public.autolazi_planul_meu() to authenticated;
