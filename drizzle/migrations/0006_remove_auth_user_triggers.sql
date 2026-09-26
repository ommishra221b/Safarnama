-- Profiles are kept in sync by the app itself; no triggers on the auth schema.
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_auth_user_updated on auth.users;
drop function if exists public.handle_new_user();