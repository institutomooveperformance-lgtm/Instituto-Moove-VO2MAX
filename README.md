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
- [ ] **Limpar os dados fictícios.** `index.html` embute 3 alunos, 2 professores
      e 2 avaliações de exemplo (`DEFAULT_ALUNOS`, `DEFAULT_PROFESSORES`,
      `DEFAULT_AVALIACOES`), que aparecem como reais no primeiro acesso de cada
      aparelho.
- [ ] **Conferir a fórmula de VO₂.** O código calcula `VO₂ = velocidade × 3,5`,
      mas a equação ACSM para corrida a 0% de inclinação é
      `VO₂ = 3,33 × velocidade(km/h) + 3,5`. Os METs saem de
      `velocidade × 3,5 / 3,5`, que é sempre igual à velocidade. Como a
      classificação Cooper deriva desse VO₂, os laudos ficam deslocados.

## Sincronização entre aparelhos

Opcional e desligada por padrão — sem configurar nada, todos os dados ficam no
`localStorage` do aparelho.

Para ligar, cole a URL de um **Google Apps Script Web App** no modal
*⚙️ Sincronização*. O código `.gs` pronto está dentro do próprio modal. A partir
daí o app faz merge por timestamp (registro mais recente vence) a cada 30
segundos, com lista de exclusões para que deleções não voltem de outro aparelho.

Dois limites importantes dessa abordagem:

- **Sem autenticação.** O Web App é implantado como "Qualquer pessoa", e quem
  tiver a URL lê e sobrescreve a base inteira — incluindo nome, telefone,
  e-mail, idade, peso e histórico de saúde de pessoas identificadas. Isso é dado
  pessoal sensível pela LGPD (art. 5º, II).
- **Teto de 9 KB.** Os dados são gravados num único `ScriptProperty`, cujo limite
  é 9 KB por valor. Cada avaliação com snapshot de estágios ocupa ~1,5 KB, então
  a sincronização começa a falhar silenciosamente por volta da sétima avaliação.
  Apesar do nome, o script não escreve em planilha alguma.

Para uso real com alunos em vários aparelhos, o caminho é trocar essa camada por
Supabase (Postgres + Auth + Row Level Security) ou Firestore. O app segue
estático; só muda a função de sync.

## Backup

O modal de sincronização exporta e importa um `.json` com a base completa,
independente da nuvem estar configurada.
