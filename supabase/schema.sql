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
-- 3. VINCULAR AS CONTAS DE LOGIN AOS PROFESSORES
--
-- Há um ovo-e-galinha: as políticas só liberam quem já é professor, e no banco
-- vazio ninguém é. Este bloco resolve criando uma linha em 'professores' para
-- cada conta de login que ainda não tenha uma, puxando o e-mail de auth.users.
--
-- Antes de rodar, crie as contas em Authentication → Users → Add user,
-- marcando 'Auto Confirm User'. Depois rode este bloco uma vez. Pode rodar de
-- novo sem duplicar: só cria para quem ainda não está vinculado.
--
-- O nome sai do e-mail e o CREF nasce vazio — ambos se corrigem pelo próprio
-- app, em 'Gestão de Professores & Avaliadores', depois do primeiro login.
-- ---------------------------------------------------------------------------

insert into public.professores (id, nome, cref, email, ativo, user_id)
select
  'p_' || replace(u.id::text, '-', ''),
  initcap(replace(split_part(u.email, '@', 1), '.', ' ')),
  '',
  u.email,
  true,
  u.id
from auth.users u
where u.email is not null
  and not exists (select 1 from public.professores p where p.user_id = u.id);

-- Confirmação: deve listar um professor por conta de login criada.
select id, nome, email, ativo, user_id from public.professores order by nome;

-- ---------------------------------------------------------------------------
-- 4. PROTEÇÃO DA COLUNA QUE AUTORIZA O ACESSO
--
-- As políticas acima deixam qualquer professor ativo escrever em qualquer linha
-- de 'professores' — o que é adequado para nome, CREF e telefone, mas não para
-- user_id: é essa coluna que concede o acesso. Sem a proteção abaixo, um
-- professor poderia apontar o user_id de um colega para a própria conta, ou
-- zerá-lo e derrubar o acesso dele.
--
-- O gatilho congela user_id para qualquer chamada vinda do app (papel
-- 'authenticated'). Só a Edge Function, que usa service_role, atravessa. Assim
-- o vínculo de acesso passa a ser alterável apenas pelo caminho que verifica
-- quem está pedindo.
-- ---------------------------------------------------------------------------

create or replace function public.protege_vinculo_de_acesso()
returns trigger
language plpgsql
-- SEM security definer, de propósito: é justamente o papel de quem chama que
-- precisa ser observado, e security definer o substituiria pelo dono da função.
as $$
begin
  -- current_user é fato do Postgres, não interpretação de token: o PostgREST
  -- executa SET LOCAL ROLE conforme a chave usada — 'authenticated' para o app,
  -- 'service_role' para a Edge Function, 'postgres' para o SQL Editor. Ler as
  -- claims do JWT para isso se mostrou pouco confiável na prática.
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.user_id := null;
    else
      new.user_id := old.user_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protege_vinculo on public.professores;
create trigger protege_vinculo
  before insert or update on public.professores
  for each row execute function public.protege_vinculo_de_acesso();

-- Reparo: religa qualquer professor que tenha ficado sem vínculo, casando pelo
-- e-mail da conta de login. Roda daqui, onde current_user é postgres e o
-- gatilho não interfere.
update public.professores p
set user_id = u.id
from auth.users u
where p.user_id is null
  and lower(u.email) = lower(p.email);

-- Confirmação: todo professor que deve entrar no sistema precisa de user_id.
select id, nome, email, ativo, user_id from public.professores order by nome;
