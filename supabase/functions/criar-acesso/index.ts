// Edge Function: criar-acesso
//
// Cria uma conta de login para um professor e a vincula ao registro dele em
// public.professores.
//
// Por que isto vive no servidor: criar usuário é operação administrativa e
// exige a chave service_role, que ignora todo o Row Level Security. Essa chave
// não pode existir no navegador — quem a obtivesse teria controle total sobre o
// histórico clínico dos alunos. Aqui ela fica nas variáveis de ambiente da
// função, que o Supabase injeta automaticamente e o cliente nunca enxerga.

const ORIGENS_PERMITIDAS = [
  'https://instituto-moove-vo2max.pages.dev',
  'http://localhost:8740',
];

function cors(origem: string | null): Record<string, string> {
  const permitida = origem && ORIGENS_PERMITIDAS.includes(origem)
    ? origem
    : ORIGENS_PERMITIDAS[0];
  return {
    'Access-Control-Allow-Origin': permitida,
    'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

Deno.serve(async (req: Request) => {
  const origem = req.headers.get('origin');
  const cabecalhos = { ...cors(origem), 'Content-Type': 'application/json' };
  const responder = (corpo: unknown, status = 200) =>
    new Response(JSON.stringify(corpo), { status, headers: cabecalhos });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origem) });
  if (req.method !== 'POST') return responder({ erro: 'Método não permitido.' }, 405);

  const BASE = Deno.env.get('SUPABASE_URL')!;
  const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
  const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = {
    apikey: SERVICE,
    Authorization: `Bearer ${SERVICE}`,
    'Content-Type': 'application/json',
  };

  try {
    // 1. Quem está chamando? O token vem do navegador e é conferido aqui, no
    // servidor. Nada que o cliente afirme sobre si mesmo é levado em conta.
    const autorizacao = req.headers.get('Authorization') || '';
    const respUsuario = await fetch(`${BASE}/auth/v1/user`, {
      headers: { apikey: ANON, Authorization: autorizacao },
    });
    if (!respUsuario.ok) return responder({ erro: 'Sessão inválida. Entre novamente.' }, 401);
    const usuario = await respUsuario.json();

    // 2. Quem chama precisa ser professor ativo. Esta consulta usa service_role
    // de propósito: o RLS não pode julgar quem tem direito de criar acesso,
    // porque ele já pressupõe a resposta que estamos tentando descobrir.
    const respProf = await fetch(
      `${BASE}/rest/v1/professores?user_id=eq.${usuario.id}&ativo=is.true&select=id,nome`,
      { headers: admin },
    );
    const professores = await respProf.json();
    if (!Array.isArray(professores) || professores.length === 0) {
      return responder({ erro: 'Apenas professores ativos podem criar acessos.' }, 403);
    }

    // 3. Validação da entrada.
    const corpo = await req.json().catch(() => ({}));
    const email = String(corpo.email || '').trim().toLowerCase();
    const senha = String(corpo.senha || '');
    const nome = String(corpo.nome || '').trim();
    const cref = String(corpo.cref || '').trim();
    const telefone = String(corpo.telefone || '').trim();

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return responder({ erro: 'E-mail inválido.' }, 400);
    if (senha.length < 12) return responder({ erro: 'A senha precisa ter ao menos 12 caracteres.' }, 400);
    if (!nome) return responder({ erro: 'Informe o nome do professor.' }, 400);

    // 4. Cria a conta já confirmada: quem autoriza é o professor ativo que está
    // chamando, então não há e-mail de confirmação a esperar.
    const respNova = await fetch(`${BASE}/auth/v1/admin/users`, {
      method: 'POST',
      headers: admin,
      body: JSON.stringify({ email, password: senha, email_confirm: true }),
    });
    const nova = await respNova.json();
    if (!respNova.ok) {
      const msg = String(nova.msg || nova.message || nova.error_description || '');
      if (/already|exists|registered/i.test(msg)) {
        return responder({ erro: 'Já existe uma conta com este e-mail.' }, 409);
      }
      return responder({ erro: msg || 'Não foi possível criar a conta.' }, 400);
    }

    // 5. Vincula ao registro de professor. Se já existe um com este e-mail, ele
    // é reaproveitado, para não duplicar o avaliador na lista de assinaturas.
    const respExiste = await fetch(
      `${BASE}/rest/v1/professores?email=eq.${encodeURIComponent(email)}&select=id`,
      { headers: admin },
    );
    const existentes = await respExiste.json();
    const linha = {
      id: (Array.isArray(existentes) && existentes[0]?.id) || 'p_' + Date.now(),
      nome,
      cref,
      telefone,
      email,
      ativo: true,
      user_id: nova.id,
      atualizado_em: new Date().toISOString(),
    };

    const respLinha = await fetch(`${BASE}/rest/v1/professores?on_conflict=id`, {
      method: 'POST',
      headers: { ...admin, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify([linha]),
    });

    if (!respLinha.ok) {
      // A conta chegou a existir mas ficou sem vínculo. Desfaz, senão sobra um
      // usuário órfão que não entra em lugar nenhum e ainda bloqueia o e-mail
      // numa próxima tentativa.
      await fetch(`${BASE}/auth/v1/admin/users/${nova.id}`, { method: 'DELETE', headers: admin });
      return responder({ erro: 'Não foi possível vincular o acesso. Nada foi salvo.' }, 500);
    }

    return responder({ ok: true, nome: linha.nome, email });
  } catch (e) {
    return responder({ erro: 'Erro inesperado: ' + (e as Error).message }, 500);
  }
});
