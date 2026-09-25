-- Instituto Moove — VO2 Máximo
-- Schema e políticas de acesso do Supabase.
-- Rode este arquivo inteiro no SQL Editor do projeto (Supabase → SQL Editor → New query).
-- É seguro rodar mais de uma vez.

-- ---------------------------------------------------------------------------
-- 1. TABELAS
--
-- Os ids são TEXT, não uuid, e são gerados pelo aparelho (ex.: 'a_1727384...').
-- Isso é proposital: o app precisa continuar cadastrando aluno e registrando
-- estágio com o wi-fi caído no meio de um teste, sincronizando depois. Se o id
-- dependesse do banco, nada poderia ser criado offline.
--
-- 'atualizado_em' é o árbitro de conflito entre aparelhos: na sincronização, a
-- versão mais recente vence. Todo write do app preenche esse campo.
-- ---------------------------------------------------------------------------

create table if not exists public.professores (
  id            text primary key,
  nome          text not null,
  cref          text,
  telefone      text,
  email         text,
  ativo         boolean not null default true,
  -- Liga o professor à conta de login. É esta coluna que autoriza o acesso:
  -- quem não estiver aqui não enxerga nada, mesmo autenticado.
  user_id       uuid references auth.users(id) on delete set null,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.alunos (
  id            text primary key,
  nome          text not null,
  idade         integer,
  sexo          text,
  peso          numeric(5,2),
  altura        numeric(4,2),
  telefone      text,
  email         text,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.avaliacoes (
  id                text primary key,
  aluno_id          text references public.alunos(id) on delete cascade,
  aluno_nome        text,
  data              text,          -- data de exibição, dd/mm/aaaa, como o app já usa
  realizado_em      bigint,        -- timestamp epoch, para ordenação
  vel_final         numeric(4,1),
  vo2_max           numeric(5,1),
  mets_max          numeric(5,1),
  duracao_segundos  integer,
  fc_pico           integer,
  fc_60s            integer,
  fc_120s           integer,
  queda_1min        integer,
  queda_2min        integer,
  classificacao     text,
  avaliador         text,
  obs               text,
  -- Os estágios ficam em jsonb, e não numa tabela filha, porque são um
  -- retrato imutável do teste: uma vez salvos, nunca são consultados campo a
  -- campo nem editados. Uma tabela filha só traria junção sem benefício.
  estagios          jsonb not null default '[]'::jsonb,
  config_protocolo  jsonb not null default '{}'::jsonb,
  atualizado_em     timestamptz not null default now()
);

create index if not exists avaliacoes_aluno_idx on public.avaliacoes (aluno_id);

-- Lápides de exclusão. Sem isto, apagar um aluno no tablet não o apagaria no
-- computador: na sincronização seguinte ele voltaria, vindo do aparelho que
-- ainda o tinha.
create table if not exists public.excluidos (
  tipo        text not null check (tipo in ('alunos', 'professores', 'avaliacoes')),
  registro_id text not null,
  excluido_em timestamptz not null default now(),
  primary key (tipo, registro_id)
);

-- Configuração do protocolo, compartilhada pelo instituto (linha única).
create table if not exists public.config (
  id            integer primary key default 1 check (id = 1),
  protocolo     jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. QUEM PODE ACESSAR
--
-- ATENÇÃO: a chave anon fica visível no código do app, que é público. Ela não
-- é segredo e não precisa ser. Quem protege os dados é o RLS abaixo.
--
-- O cadastro público de contas está ABERTO neste projeto. Por isso as
-- políticas NÃO se baseiam em "estar autenticado" — se baseiam em "ser um
-- professor cadastrado e ativo". Alguém que crie uma conta por fora fica
-- autenticado, mas não enxerga uma única linha.
-- ---------------------------------------------------------------------------

create or replace function public.eh_avaliador()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.professores
    where user_id = auth.uid() and ativo
  );
$$;

alter table public.professores alter column ativo set default true;

alter table public.professores enable row level security;
alter table public.alunos      enable row level security;
alter table public.avaliacoes  enable row level security;
alter table public.excluidos   enable row level security;
alter table public.config      enable row level security;

do $$
declare t text;
begin
  foreach t in array array['professores','alunos','avaliacoes','excluidos','config'] loop
    execute format('drop policy if exists avaliadores_leem on public.%I', t);
    execute format('drop policy if exists avaliadores_acessam on public.%I', t);
    -- FOR ALL já cobre select, insert, update e delete.
    execute format(
      'create policy avaliadores_acessam on public.%I for all to authenticated '
      'using (public.eh_avaliador()) with check (public.eh_avaliador())', t);
  end loop;
end $$;

-- Privilégios: apenas 'authenticated'. O papel 'anon' — o de quem abre o site
-- sem fazer login — não recebe nada, então a chave pública sozinha não lê nada.
grant usage on schema public to authenticated;
grant select, insert, update, delete
  on public.professores, public.alunos, public.avaliacoes, public.excluidos, public.config
  to authenticated;
revoke all on public.professores, public.alunos, public.avaliacoes, public.excluidos, public.config from anon;

-- ---------------------------------------------------------------------------
-- 3. CADASTRAR O PRIMEIRO PROFESSOR
--
-- Há um ovo-e-galinha: as políticas só liberam quem já é professor, e no banco
-- vazio ninguém é. O primeiro registro precisa ser criado aqui, uma vez.
--
-- Passo 1 — crie a conta de login em
--           Authentication → Users → Add user (e-mail + senha).
-- Passo 2 — troque os dados abaixo pelos reais e rode este bloco.
--           Repita para cada professor. Do segundo em diante, dá para cadastrar
--           pelo próprio app.
-- ---------------------------------------------------------------------------

-- insert into public.professores (id, nome, cref, telefone, email, ativo, user_id)
-- select
--   'p_' || extract(epoch from now())::bigint,
--   'Prof. Nome Completo',
--   '000000-G/SP',
--   '(11) 90000-0000',
--   'professor@institutomoove.com.br',
--   true,
--   id
-- from auth.users
-- where email = 'professor@institutomoove.com.br'
-- on conflict (id) do nothing;
