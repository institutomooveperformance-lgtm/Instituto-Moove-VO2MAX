# Instituto Moove — Teste de VO₂ Máximo

Web app para conduzir e registrar testes de VO₂ máximo em esteira com protocolo
de rampa progressiva. Gestão de alunos e avaliadores, cronômetro de estágios,
cálculo de desfecho, recuperação cardíaca, laudos imprimíveis e envio de
resultados por WhatsApp / e-mail.

## Stack

Site **100% estático**: HTML + CSS + JavaScript puro, sem build e sem
dependências para instalar. Não há `npm install`, nem passo de compilação.

| Arquivo | Papel |
|---|---|
| `index.html` | O app inteiro (markup, estilos e lógica) |
| `basecoat.cdn.min.css` | Folha de estilos base, servida localmente |
| `_headers` | Cabeçalhos de segurança (Cloudflare Pages / Netlify) |
| `.nojekyll` | Impede o GitHub Pages de ignorar arquivos com `_` |

A única dependência externa em runtime é a fonte Inter, do Google Fonts. Se
quiser eliminá-la também, baixe os `.woff2` para o repo e troque o `<link>` por
um `@font-face` local.

## Rodar localmente

Abrir o `index.html` no navegador já funciona. Para um ambiente mais próximo do
de produção (origem HTTP real, como em qualquer host):

```sh
python -m http.server 8000
# abra http://localhost:8000
```

## Deploy

O app é estático, então **qualquer** host de arquivos serve. Três caminhos, do
mais rápido ao mais completo.

### Opção A — GitHub Pages (~5 min, grátis)

1. `git push` para a branch `main`.
2. No GitHub: **Settings → Pages**.
3. Em *Source*, escolha **Deploy from a branch**; branch `main`, pasta `/ (root)`.
4. Salve. Em cerca de um minuto o app fica em
   `https://<usuario>.github.io/Instituto-Moove-VO2MAX/`.

HTTPS é automático. Limitação: o GitHub Pages **não aplica o `_headers`** — sem
CSP nem proteção contra iframe. E a página é sempre pública.

### Opção B — Cloudflare Pages ou Netlify (~10 min, grátis) — recomendado

1. Crie a conta e escolha *Import an existing Git repository*.
2. Autorize o GitHub e selecione este repositório.
3. Nas configurações de build, deixe **em branco**:
   - *Build command*: vazio (não há build)
   - *Output / publish directory*: `/` (a raiz)
4. Deploy. Cada `git push` republica automaticamente.

Vantagens sobre o Pages: **domínio próprio** com SSL (ex.
`vo2.institutomoove.com.br`), os cabeçalhos de segurança do `_headers` passam a
valer, e o Netlify oferece **proteção por senha** nos planos pagos — a forma mais
simples de fechar o acesso sem escrever código.

### Opção C — PWA instalável (trabalho adicional)

Adicionar `manifest.json`, ícones e um service worker faz o app **instalar na
tela inicial** do celular ou tablet, abrir em tela cheia e funcionar offline de
verdade. Para um app operado ao lado da esteira, vale o esforço. Combina com a
opção A ou B.

## Após o deploy, verificar

- [ ] **O CSP não quebrou nada.** É o único item de risco do `_headers`. Abra o
      console do navegador e confirme que não há erros de *Content Security
      Policy*. Se a sincronização falhar, é provável que o Apps Script esteja
      redirecionando para um domínio fora do `connect-src` — acrescente-o à
      diretiva ou remova a linha do CSP.
## Cálculo do VO₂ máximo

O app estima `VO₂ = velocidade final (km/h) × 3,5`, e os METs saem de `VO₂ / 3,5`
— o que faz os METs coincidirem numericamente com a velocidade em km/h.

**Essa é uma escolha deliberada do Instituto Moove, não a equação da ACSM.** Fica
registrado aqui para que ninguém a "corrija" por engano. A equação da ACSM para
corrida a 0% de inclinação seria `VO₂ = 3,33 × velocidade + 3,5`, que devolve de
1 a 2 mL/kg/min mais e pode deslocar a classificação Cooper de alunos próximos
das faixas:

| Velocidade final | Conta atual | Equação ACSM |
|---|---|---|
| 8,0 km/h  | 28,0 | 30,2 |
| 10,0 km/h | 35,0 | 36,8 |
| 12,0 km/h | 42,0 | 43,5 |
| 15,0 km/h | 52,5 | 53,5 |

As **tabelas normativas** de classificação (Cooper Institute / ACSM) e os
**critérios de interrupção** do teste seguem as referências originais — o desvio
acima vale só para a estimativa do VO₂.

## Tema claro e escuro

O botão 🌙 / ☀️ no cabeçalho alterna, e a escolha fica guardada por aparelho em
`localStorage`. A tela de login tem o próprio seletor, para quem prefere escuro
não levar um clarão antes de conseguir entrar.

Sem escolha salva, o app segue a preferência do sistema operacional e acompanha
mudanças em tempo real. Uma escolha explícita vence o sistema **nas duas
direções** — tema claro num aparelho em modo noturno funciona, e vice-versa.

Um script no `<head>` aplica o tema antes da primeira pintura. Sem isso, quem
prefere escuro veria um lampejo branco a cada carregamento.

### Se for mexer nas cores

Não há cor fixa no app: tudo passa por tokens CSS definidos em `:root`, com a
paleta escura sobrescrevendo os mesmos nomes. As únicas exceções deliberadas são
o verde da marca do WhatsApp e a paleta categórica dos gráficos, que funcionam
nos dois temas.

**Laudos são sempre impressos claros.** O bloco `@media print` redefine os
tokens para a paleta clara, revertendo a página inteira de uma vez — tinta
escura em papel branco, independentemente do tema na tela.

## Acesso e sincronização

O app exige **login por professor** e sincroniza com um projeto Supabase
(Postgres). Cada avaliador tem sua própria conta, o que faz o campo "Avaliador"
do laudo significar algo de verdade e permite revogar o acesso de uma pessoa
sem trocar a senha de todo mundo.

O esquema e as políticas de acesso estão em [`supabase/schema.sql`](supabase/schema.sql),
que pode ser rodado mais de uma vez com segurança.

### Como os dados fluem

O `localStorage` continua sendo a camada de trabalho; o Supabase é o destino da
sincronização. Isso é deliberado: numa academia a conexão cai, e o app precisa
seguir registrando estágios com o wi-fi fora, enviando quando a rede voltar.
Pela mesma razão os ids são gerados pelo aparelho, e não pelo banco — um id
vindo do servidor impediria qualquer cadastro offline.

O conflito entre aparelhos se resolve por `atualizado_em`: a versão mais recente
vence. Exclusões viram lápides na tabela `excluidos`, sem o que apagar um aluno
no tablet não o apagaria no computador — ele voltaria na sincronização seguinte,
vindo do aparelho que ainda o tinha.

### Sobre a chave no código

A chave anon do Supabase fica visível no `index.html`, que está num repositório
público. **Isso é normal e esperado:** ela identifica o projeto, não autoriza
nada. Quem protege os dados é o Row Level Security.

As políticas não se baseiam em "estar autenticado", e sim em **"ser um professor
cadastrado e ativo"**, verificado pela função `eh_avaliador()`. A diferença
importa: com o cadastro público aberto, qualquer pessoa poderia criar uma conta
e ficar autenticada — mas sem uma linha em `professores` não enxerga nada. O
papel `anon` não recebe privilégio algum.

### Criar acesso para um novo professor

Pelo próprio app: **Gestão de Professores & Avaliadores → 🔑 Criar Acesso ao
Sistema**. Qualquer professor ativo pode fazer isso, sem depender do painel do
Supabase.

Atenção à distinção: **"+ Adicionar Professor" não cria login.** Ele só
disponibiliza o nome para assinar laudos. Quem dá acesso ao sistema é o botão
"Criar Acesso ao Sistema".

A senha provisória aparece uma única vez, na tela. Ela não fica guardada em
lugar nenhum e não pode ser consultada depois — anote e entregue por um canal
seguro. Se perder, crie outra pelo painel do Supabase.

Para revogar, desmarque **Ativo** na tabela de professores: a política exige
`ativo`, então o acesso cai na sincronização seguinte.

### Por que criar login exige uma Edge Function

Criar usuário é operação administrativa e exige a chave `service_role`, que
ignora todo o RLS. Essa chave não pode viver no navegador — quem a obtivesse
teria controle total sobre o histórico clínico dos alunos.

A função [`supabase/functions/criar-acesso`](supabase/functions/criar-acesso/index.ts)
roda no servidor do Supabase, onde a chave fica em variável de ambiente. Ela
confere **no servidor** se quem chamou é um professor ativo antes de criar
qualquer conta; nada que o cliente afirme sobre si mesmo é levado em conta.

Um gatilho no banco (seção 4 do schema) congela a coluna `user_id` para
chamadas vindas do app. Sem ele, qualquer professor poderia apontar o `user_id`
de um colega para a própria conta, ou zerá-lo e derrubar o acesso dele. Só a
Edge Function, que usa `service_role`, consegue alterar esse vínculo.

### Publicar a Edge Function

Necessário uma vez, e a cada alteração da função.

Pela CLI:

```sh
npx supabase login
npx supabase link --project-ref pbmveouilfkqnbyglyom
npx supabase functions deploy criar-acesso
```

Ou pelo painel: **Edge Functions → Deploy a new function**, com o nome
`criar-acesso`, colando o conteúdo do `index.ts`.

Não é preciso configurar segredo algum: `SUPABASE_URL`, `SUPABASE_ANON_KEY` e
`SUPABASE_SERVICE_ROLE_KEY` são injetadas automaticamente.

Se o domínio do site mudar, atualize `ORIGENS_PERMITIDAS` no topo da função e
publique de novo — senão o navegador bloqueia a chamada por CORS.

## Backup

O modal de Conta & Sincronização exporta e importa um `.json` com a base
completa. Funciona independentemente da nuvem, e serve como rede de segurança
antes de qualquer operação arriscada.
