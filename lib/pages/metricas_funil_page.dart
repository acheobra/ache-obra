import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MetricasFunilPage extends StatefulWidget {
  const MetricasFunilPage({super.key});

  @override
  State<MetricasFunilPage> createState() => _MetricasFunilPageState();
}

class _MetricasFunilPageState extends State<MetricasFunilPage> {
  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _topo = Color(0xFF0D1B2A);
  static const Color _card = Color(0xFF101B2B);
  static const Color _card2 = Color(0xFF1B3047);
  static const Color _laranja = Color(0xFFFF8C00);
  static const Color _verde = Color(0xFF18D77D);
  static const Color _vermelho = Color(0xFFFF5252);
  static const Color _cinza = Color(0xFFAAB4C3);

  final SupabaseClient _supabase = Supabase.instance.client;

  late DateTime _dataInicial;
  late DateTime _dataFinal;

  bool _carregando = true;
  String? _erro;

  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _acessos = [];
  List<Map<String, dynamic>> _demandas = [];
  List<Map<String, dynamic>> _conversas = [];
  List<Map<String, dynamic>> _mensagens = [];
  List<Map<String, dynamic>> _orcamentos = [];
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _assinaturas = [];
  List<Map<String, dynamic>> _assinaturasGoogle = [];
  List<Map<String, dynamic>> _pagamentosAvulsos = [];
  List<Map<String, dynamic>> _pagamentosRecorrentes = [];

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _dataFinal = DateTime(agora.year, agora.month, agora.day, 23, 59, 59, 999);
    _dataInicial = _dataFinal.subtract(const Duration(days: 29));
    _dataInicial = DateTime(
      _dataInicial.year,
      _dataInicial.month,
      _dataInicial.day,
    );
    _carregar();
  }

  DateTime? _parseData(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor.toLocal();
    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  String _isoInicio() => _dataInicial.toUtc().toIso8601String();
  String _isoFim() => _dataFinal.toUtc().toIso8601String();

  String _dataDateInicio() => '${_dataInicial.year.toString().padLeft(4, '0')}-'
      '${_dataInicial.month.toString().padLeft(2, '0')}-'
      '${_dataInicial.day.toString().padLeft(2, '0')}';

  String _dataDateFim() => '${_dataFinal.year.toString().padLeft(4, '0')}-'
      '${_dataFinal.month.toString().padLeft(2, '0')}-'
      '${_dataFinal.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> _buscar(
    String tabela,
    String campos,
    String campoData, {
    bool somenteData = false,
  }) async {
    try {
      dynamic q = _supabase.from(tabela).select(campos);
      if (somenteData) {
        q = q.gte(campoData, _dataDateInicio()).lte(campoData, _dataDateFim());
      } else {
        q = q.gte(campoData, _isoInicio()).lte(campoData, _isoFim());
      }
      final r = await q;
      return List<Map<String, dynamic>>.from(r as List);
    } catch (e) {
      throw Exception('$tabela: $e');
    }
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resultados = await Future.wait([
        _buscar(
          'tab_usuarios',
          'id,usuario_tipo,nome_plano_ativo,recorrente,plano_data_ativacao',
          'dt_cadastro',
          somenteData: true,
        ),
        _buscar(
          'tab_acessos',
          'usuario_id,sessao_id,data_hora_acesso,tipo_acesso',
          'data_hora_acesso',
        ),
        _buscar(
          'tab_demandas_clientes',
          'id,cliente_id,status,criado_em',
          'criado_em',
        ),
        _buscar(
          'tab_conversas',
          'id,demanda_id,cliente_id,outro_usuario_id,created_at',
          'created_at',
        ),
        _buscar(
          'tab_mensagens',
          'id,conversa_id,remetente_id,destino_id,created_at,lida',
          'created_at',
        ),
        _buscar(
          'tab_orcamentos',
          'id,usuario_id,criado_em',
          'criado_em',
        ),
        _buscar(
          'tab_pedidos',
          'id,usuario_id,status,valor,created_at,origem_tipo',
          'created_at',
        ),
        _buscar(
          'tab_assinaturas',
          'id,usuario_id,plano_id,status_assinatura,data_inicio,data_ultimo_pagamento',
          'data_inicio',
        ),
        _buscar(
          'tab_assinaturas_google',
          'id,usuario_id,plano_id,status_assinatura,data_inicio,data_ultimo_pagamento,tipo_compra,recorrente',
          'data_inicio',
        ),
        _buscar(
          'tab_pagamentos_avulsos',
          'id,usuario_id,status,valor,data_pagamento,created_at,origem_tipo',
          'created_at',
        ),
        _buscar(
          'tab_pagamentos_recorrentes',
          'id,usuario_id,plano_id,status,status_efi,valor,data_cobranca,data_pagamento,created_at',
          'created_at',
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _usuarios = resultados[0];
        _acessos = resultados[1];
        _demandas = resultados[2];
        _conversas = resultados[3];
        _mensagens = resultados[4];
        _orcamentos = resultados[5];
        _pedidos = resultados[6];
        _assinaturas = resultados[7];
        _assinaturasGoogle = resultados[8];
        _pagamentosAvulsos = resultados[9];
        _pagamentosRecorrentes = resultados[10];
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  Set<String> _ids(List<Map<String, dynamic>> lista, String campo) {
    return lista
        .map((e) => e[campo]?.toString())
        .whereType<String>()
        .where((e) => e.trim().isNotEmpty)
        .toSet();
  }

  Set<String> _usuariosConversas() {
    final s = <String>{};
    for (final c in _conversas) {
      final a = c['cliente_id']?.toString();
      final b = c['outro_usuario_id']?.toString();
      if (a != null && a.isNotEmpty) s.add(a);
      if (b != null && b.isNotEmpty) s.add(b);
    }
    return s;
  }

  Set<String> _usuariosMensagens() {
    final s = <String>{};
    for (final m in _mensagens) {
      final a = m['remetente_id']?.toString();
      final b = m['destino_id']?.toString();
      if (a != null && a.isNotEmpty) s.add(a);
      if (b != null && b.isNotEmpty) s.add(b);
    }
    return s;
  }

  Set<String> _usuariosAssinaturas() {
    return {
      ..._ids(_assinaturas, 'usuario_id'),
      ..._ids(_assinaturasGoogle, 'usuario_id'),
    };
  }

  bool _pagamentoConfirmado(Map<String, dynamic> p) {
    return p['data_pagamento'] != null;
  }

  Set<String> _usuariosPagantes() {
    final s = <String>{};
    for (final p in _pagamentosAvulsos) {
      if (_pagamentoConfirmado(p)) {
        final id = p['usuario_id']?.toString();
        if (id != null && id.isNotEmpty) s.add(id);
      }
    }
    for (final p in _pagamentosRecorrentes) {
      if (_pagamentoConfirmado(p)) {
        final id = p['usuario_id']?.toString();
        if (id != null && id.isNotEmpty) s.add(id);
      }
    }
    return s;
  }

  int _pagamentosConfirmados() {
    return _pagamentosAvulsos.where(_pagamentoConfirmado).length +
        _pagamentosRecorrentes.where(_pagamentoConfirmado).length;
  }

  double _receitaConfirmada() {
    double total = 0;
    for (final p in [..._pagamentosAvulsos, ..._pagamentosRecorrentes]) {
      if (_pagamentoConfirmado(p)) {
        total += double.tryParse('${p['valor'] ?? 0}') ?? 0;
      }
    }
    return total;
  }

  double _taxa(int atual, int anterior) {
    if (anterior <= 0) return 0;
    return (atual / anterior) * 100;
  }

  String _pct(double n) => '${n.toStringAsFixed(1).replaceAll('.', ',')}%';

  String _moeda(double n) {
    final s = n.toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $s';
  }

  String _fmtData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<DateTime?> _selecionarDataHora(
    BuildContext context,
    DateTime atual,
    String titulo,
  ) async {
    DateTime temp = atual;

    final data = await showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        int dia = temp.day;
        int mes = temp.month;
        int ano = temp.year;
        int hora = temp.hour;
        int minuto = temp.minute;

        int diasNoMes(int a, int m) => DateTime(a, m + 1, 0).day;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void corrigirDia() {
              final max = diasNoMes(ano, mes);
              if (dia > max) dia = max;
            }

            Widget dd(
              String label,
              int value,
              List<int> values,
              ValueChanged<int?> onChanged,
            ) {
              return SizedBox(
                width: 112,
                child: DropdownButtonFormField<int>(
                  value: value,
                  dropdownColor: _card2,
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: const TextStyle(color: _cinza),
                    border: const OutlineInputBorder(),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  items: values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.toString().padLeft(2, '0')),
                        ),
                      )
                      .toList(),
                  onChanged: onChanged,
                ),
              );
            }

            return AlertDialog(
              backgroundColor: _card,
              title: Text(
                titulo,
                style: const TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  children: [
                    dd(
                      'Dia',
                      dia,
                      List.generate(diasNoMes(ano, mes), (i) => i + 1),
                      (v) => setLocal(() => dia = v ?? dia),
                    ),
                    dd(
                      'Mês',
                      mes,
                      List.generate(12, (i) => i + 1),
                      (v) => setLocal(() {
                        mes = v ?? mes;
                        corrigirDia();
                      }),
                    ),
                    dd(
                      'Ano',
                      ano,
                      List.generate(
                          DateTime.now().year - 2019 + 6, (i) => 2020 + i),
                      (v) => setLocal(() {
                        ano = v ?? ano;
                        corrigirDia();
                      }),
                    ),
                    dd(
                      'Hora',
                      hora,
                      List.generate(24, (i) => i),
                      (v) => setLocal(() => hora = v ?? hora),
                    ),
                    dd(
                      'Minuto',
                      minuto,
                      List.generate(60, (i) => i),
                      (v) => setLocal(() => minuto = v ?? minuto),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _laranja),
                  onPressed: () {
                    Navigator.pop(
                      ctx,
                      DateTime(ano, mes, dia, hora, minuto),
                    );
                  },
                  child: const Text(
                    'Confirmar',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return data;
  }

  Future<void> _alterarInicio() async {
    final d = await _selecionarDataHora(
      context,
      _dataInicial,
      'Data e hora inicial',
    );
    if (d == null) return;
    if (d.isAfter(_dataFinal)) {
      _snack('A data inicial não pode ser maior que a data final.');
      return;
    }
    setState(() => _dataInicial = d);
    await _carregar();
  }

  Future<void> _alterarFim() async {
    final d = await _selecionarDataHora(
      context,
      _dataFinal,
      'Data e hora final',
    );
    if (d == null) return;
    if (d.isBefore(_dataInicial)) {
      _snack('A data final não pode ser menor que a data inicial.');
      return;
    }
    setState(() => _dataFinal = d);
    await _carregar();
  }

  Future<void> _atalho(int dias) async {
    final agora = DateTime.now();
    setState(() {
      _dataFinal = DateTime(
        agora.year,
        agora.month,
        agora.day,
        23,
        59,
        59,
        999,
      );
      final ini = _dataFinal.subtract(Duration(days: dias - 1));
      _dataInicial = DateTime(ini.year, ini.month, ini.day);
    });
    await _carregar();
  }

  Future<void> _todoPeriodo() async {
    setState(() {
      _dataInicial = DateTime(2020, 1, 1);
      final agora = DateTime.now();
      _dataFinal = DateTime(
        agora.year,
        agora.month,
        agora.day,
        23,
        59,
        59,
        999,
      );
    });
    await _carregar();
  }

  void _snack(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _topo,
        foregroundColor: Colors.white,
        title: const Text('Métricas de Funil'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: _laranja),
            )
          : _erro != null
              ? _erroWidget()
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _periodo(),
                      const SizedBox(height: 20),
                      _resumo(),
                      const SizedBox(height: 20),
                      _funilPrincipal(),
                      const SizedBox(height: 20),
                      _funilCliente(),
                      const SizedBox(height: 20),
                      _funilMonetizacao(),
                      const SizedBox(height: 20),
                      _atividade(),
                      const SizedBox(height: 20),
                      _observacao(),
                    ],
                  ),
                ),
    );
  }

  Widget _periodo() {
    String dt(DateTime d) =>
        '${_fmtData(d)} ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

    return _secao(
      titulo: 'Período do funil',
      subtitulo:
          'Os eventos são recalculados pelo intervalo selecionado. Cadastros usam dt_cadastro; os demais eventos usam seus timestamps próprios.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _botaoPeriodo(
            Icons.calendar_month,
            'Inicial: ${dt(_dataInicial)}',
            _alterarInicio,
          ),
          _botaoPeriodo(
            Icons.calendar_month,
            'Final: ${dt(_dataFinal)}',
            _alterarFim,
          ),
          _atalhoBotao('7 dias', () => _atalho(7)),
          _atalhoBotao('30 dias', () => _atalho(30)),
          _atalhoBotao('90 dias', () => _atalho(90)),
          _atalhoBotao('1 ano', () => _atalho(365)),
          TextButton(
            onPressed: _todoPeriodo,
            child: const Text(
              'Todo o período',
              style: TextStyle(color: _laranja),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumo() {
    final cadastrados = _ids(_usuarios, 'id').length;
    final acessaram = _ids(_acessos, 'usuario_id').length;
    final interagiram = {
      ..._ids(_demandas, 'cliente_id'),
      ..._usuariosConversas(),
      ..._usuariosMensagens(),
      ..._ids(_orcamentos, 'usuario_id'),
    }.length;
    final pagantes = _usuariosPagantes().length;

    return _secao(
      titulo: 'Resumo do funil',
      subtitulo: 'Usuários únicos em cada grupo durante o período selecionado.',
      child: LayoutBuilder(
        builder: (context, c) {
          final largura = c.maxWidth;
          final cols = largura >= 1050 ? 4 : (largura >= 620 ? 2 : 1);
          final w = (largura - ((cols - 1) * 12)) / cols;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi(w, 'CADASTROS', '$cadastrados', 'novos usuários',
                  Icons.person_add, _verde),
              _kpi(w, 'ACESSARAM', '$acessaram', 'usuários únicos', Icons.login,
                  _laranja),
              _kpi(w, 'INTERAGIRAM', '$interagiram', 'ações de marketplace',
                  Icons.touch_app, _laranja),
              _kpi(w, 'PAGANTES', '$pagantes', 'pagamento confirmado',
                  Icons.payments, _verde),
            ],
          );
        },
      ),
    );
  }

  Widget _funilPrincipal() {
    final cad = _ids(_usuarios, 'id');
    final acess = _ids(_acessos, 'usuario_id');
    final demanda = _ids(_demandas, 'cliente_id');
    final conversa = _usuariosConversas();
    final mensagem = _usuariosMensagens();
    final orc = _ids(_orcamentos, 'usuario_id');
    final pag = _usuariosPagantes();

    final etapas = <_Etapa>[
      _Etapa('Cadastros', cad.length, Icons.person_add),
      _Etapa('Acessaram', acess.length, Icons.login),
      _Etapa('Criaram demanda', demanda.length, Icons.assignment_outlined),
      _Etapa('Participaram de conversa', conversa.length, Icons.forum_outlined),
      _Etapa(
          'Participaram de mensagens', mensagem.length, Icons.message_outlined),
      _Etapa('Criaram orçamento', orc.length, Icons.request_quote_outlined),
      _Etapa('Realizaram pagamento', pag.length, Icons.payments_outlined),
    ];

    return _secao(
      titulo: 'Funil geral de utilização',
      subtitulo:
          'Mostra usuários únicos observados em cada etapa no período. As etapas não são forçadas a ser uma sequência individual quando o banco não registra um vínculo direto entre elas.',
      child: _listaEtapas(etapas),
    );
  }

  Widget _funilCliente() {
    final demandas = _ids(_demandas, 'cliente_id');
    final clientesConversa = _ids(_conversas, 'cliente_id');

    final conversasIds =
        _conversas.map((e) => e['id']?.toString()).whereType<String>().toSet();

    final clientesComMensagem = <String>{};
    for (final m in _mensagens) {
      final convId = m['conversa_id']?.toString();
      if (convId == null || !conversasIds.contains(convId)) continue;
      final remetente = m['remetente_id']?.toString();
      if (remetente != null && remetente.isNotEmpty) {
        clientesComMensagem.add(remetente);
      }
    }

    final etapas = <_Etapa>[
      _Etapa('Clientes com demanda', demandas.length, Icons.assignment),
      _Etapa('Clientes em conversa', clientesConversa.length, Icons.forum),
      _Etapa('Remetentes de mensagens', clientesComMensagem.length, Icons.chat),
    ];

    return _secao(
      titulo: 'Funil de clientes',
      subtitulo:
          'Acompanha demanda e comunicação. O banco atual não possui vínculo direto do orçamento com demanda/cliente, por isso orçamento não é apresentado como etapa sequencial deste funil.',
      child: _listaEtapas(etapas),
    );
  }

  Widget _funilMonetizacao() {
    final cad = _ids(_usuarios, 'id');
    final assin = _usuariosAssinaturas();
    final pedido = _ids(_pedidos, 'usuario_id');
    final pag = _usuariosPagantes();

    final etapas = <_Etapa>[
      _Etapa('Usuários cadastrados', cad.length, Icons.people_alt_outlined),
      _Etapa('Iniciaram assinatura', assin.length,
          Icons.workspace_premium_outlined),
      _Etapa('Geraram pedido', pedido.length, Icons.shopping_cart_checkout),
      _Etapa('Pagamento confirmado', pag.length, Icons.verified_outlined),
    ];

    return _secao(
      titulo: 'Funil de monetização',
      subtitulo:
          'Assinaturas combinam Efí e Google. Pagamento confirmado é identificado por data_pagamento preenchida nas tabelas de pagamentos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _listaEtapas(etapas),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 800 ? 3 : 1;
              final w = (c.maxWidth - ((cols - 1) * 12)) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpi(
                    w,
                    'CONVERSÃO CADASTRO → PAGANTE',
                    _pct(_taxa(pag.length, cad.length)),
                    '${pag.length} de ${cad.length}',
                    Icons.trending_up,
                    _verde,
                  ),
                  _kpi(
                    w,
                    'PAGAMENTOS CONFIRMADOS',
                    '${_pagamentosConfirmados()}',
                    'avulsos + recorrentes',
                    Icons.check_circle_outline,
                    _verde,
                  ),
                  _kpi(
                    w,
                    'RECEITA CONFIRMADA',
                    _moeda(_receitaConfirmada()),
                    'valor dos pagamentos com data_pagamento',
                    Icons.attach_money,
                    _laranja,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _atividade() {
    final sessoes = _ids(_acessos, 'sessao_id').length;
    final conversas = _conversas.length;
    final mensagens = _mensagens.length;
    final demandas = _demandas.length;
    final orcamentos = _orcamentos.length;
    final pedidos = _pedidos.length;

    return _secao(
      titulo: 'Volume de ações',
      subtitulo:
          'Quantidade total de eventos registrados no período, complementar ao funil de usuários únicos.',
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
          final w = (c.maxWidth - ((cols - 1) * 12)) / cols;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi(w, 'SESSÕES', '$sessoes', 'sessões registradas',
                  Icons.devices, _laranja),
              _kpi(w, 'DEMANDAS', '$demandas', 'demandas criadas',
                  Icons.assignment_outlined, _laranja),
              _kpi(w, 'CONVERSAS', '$conversas', 'conversas iniciadas',
                  Icons.forum_outlined, _laranja),
              _kpi(w, 'MENSAGENS', '$mensagens', 'mensagens enviadas',
                  Icons.message_outlined, _laranja),
              _kpi(w, 'ORÇAMENTOS', '$orcamentos', 'orçamentos criados',
                  Icons.request_quote, _laranja),
              _kpi(w, 'PEDIDOS', '$pedidos', 'pedidos gerados',
                  Icons.shopping_cart, _laranja),
            ],
          );
        },
      ),
    );
  }

  Widget _listaEtapas(List<_Etapa> etapas) {
    final maximo = etapas.isEmpty
        ? 0
        : etapas.map((e) => e.valor).fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      children: List.generate(etapas.length, (i) {
        final e = etapas[i];
        final anterior = i == 0 ? null : etapas[i - 1].valor;
        final conversao = anterior == null ? 100.0 : _taxa(e.valor, anterior);
        final abandono =
            anterior == null ? 0.0 : (100 - conversao).clamp(0, 100).toDouble();
        final proporcao = maximo <= 0 ? 0.0 : e.valor / maximo;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _laranja.withOpacity(.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(e.icone, color: _laranja),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      e.titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${e.valor}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: proporcao.clamp(0, 1),
                  minHeight: 9,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(_laranja),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text(
                    i == 0
                        ? 'Base da comparação'
                        : 'Conversão da etapa anterior: ${_pct(conversao)}',
                    style: const TextStyle(color: _cinza, fontSize: 12),
                  ),
                  const Spacer(),
                  if (i > 0)
                    Text(
                      'Queda: ${_pct(abandono)}',
                      style: TextStyle(
                        color: abandono > 50 ? _vermelho : _cinza,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _observacao() {
    return _secao(
      titulo: 'Como interpretar',
      subtitulo: 'Critérios usados nesta tela',
      child: const Text(
        'Esta tela trabalha com eventos efetivamente registrados no banco. '
        'Uma pessoa pode aparecer em uma etapa posterior sem ter um evento da etapa anterior dentro do mesmo intervalo selecionado. '
        'Por isso, as taxas entre etapas representam comparação de volumes de usuários únicos no período e não uma coorte cronológica perfeita. '
        'Para pagamentos, a confirmação utiliza data_pagamento preenchida, evitando depender de nomes de status específicos do gateway. '
        'À medida que o histórico de tab_acessos e os demais eventos crescerem, o funil ficará mais representativo.',
        style: TextStyle(color: _cinza, height: 1.5),
      ),
    );
  }

  Widget _secao({
    required String titulo,
    required String subtitulo,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: _laranja,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitulo,
            style: const TextStyle(color: _cinza, fontSize: 13),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _kpi(
    double largura,
    String titulo,
    String valor,
    String detalhe,
    IconData icone,
    Color cor,
  ) {
    return SizedBox(
      width: largura,
      child: Container(
        constraints: const BoxConstraints(minHeight: 122),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      color: _cinza,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              valor,
              style: TextStyle(
                color: cor,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detalhe,
              style: const TextStyle(color: _cinza, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoPeriodo(
    IconData icon,
    String texto,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(texto),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white30),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _atalhoBotao(String texto, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _laranja,
        side: const BorderSide(color: Colors.white30),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: Text(texto),
    );
  }

  Widget _erroWidget() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _vermelho.withOpacity(.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _vermelho, size: 42),
            const SizedBox(height: 14),
            const Text(
              'Não foi possível carregar as métricas de funil.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              _erro ?? '',
              style: const TextStyle(color: _cinza),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Etapa {
  final String titulo;
  final int valor;
  final IconData icone;

  const _Etapa(this.titulo, this.valor, this.icone);
}
