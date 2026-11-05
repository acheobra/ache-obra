import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasPlanosPage extends StatefulWidget {
  const MetricasPlanosPage({super.key});

  @override
  State<MetricasPlanosPage> createState() => _MetricasPlanosPageState();
}

class _MetricasPlanosPageState extends State<MetricasPlanosPage> {
  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _card = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);
  static const Color _borda = Color(0xFF2A3D55);

  final SupabaseClient _supabase = Supabase.instance.client;

  bool _carregando = true;
  String? _erro;
  DateTime _inicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fim = DateTime.now();

  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _manuais = [];
  List<Map<String, dynamic>> _assinaturas = [];
  List<Map<String, dynamic>> _google = [];
  List<Map<String, dynamic>> _pagRec = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();
  String _norm(dynamic v) => _s(v).toLowerCase();
  double _n(dynamic v) => v is num
      ? v.toDouble()
      : double.tryParse(_s(v).replaceAll(',', '.')) ?? 0;
  bool _b(dynamic v) => v == true || _norm(v) == 'true';

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  bool _noPeriodo(DateTime? d) {
    if (d == null) return false;
    final i = DateTime(_inicio.year, _inicio.month, _inicio.day);
    final f = DateTime(_fim.year, _fim.month, _fim.day, 23, 59, 59, 999);
    return !d.isBefore(i) && !d.isAfter(f);
  }

  bool _statusAtivo(dynamic status) {
    final s = _norm(status);
    return s == 'ativo' ||
        s == 'active' ||
        s == 'paid' ||
        s == 'pago' ||
        s == 'approved' ||
        s == 'aprovado' ||
        s == 'autorizado' ||
        s == 'authorized' ||
        s == 'vigente';
  }

  bool _statusCancelado(dynamic status) {
    final s = _norm(status);
    return s.contains('cancel') || s == 'canceled' || s == 'cancelled';
  }

  bool _statusPago(dynamic status) {
    final s = _norm(status);
    return s == 'paid' ||
        s == 'pago' ||
        s == 'approved' ||
        s == 'aprovado' ||
        s == 'confirmed' ||
        s == 'confirmado' ||
        s == 'settled' ||
        s == 'concluido' ||
        s == 'concluído';
  }

  bool _planoManualNome(String nome) {
    final n = nome.toLowerCase().trim();
    return n == 'teste' ||
        n == 'cortesia' ||
        n == 'parceria' ||
        n == 'especial';
  }

  bool _planoGratisNome(String nome) {
    final n = nome.toLowerCase();
    return n.contains('gratis') ||
        n.contains('grátis') ||
        n == 'free' ||
        n.contains('gratuito');
  }

  Future<List<Map<String, dynamic>>> _select(
      String tabela, String campos) async {
    try {
      final data = await _supabase.from(tabela).select(campos);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
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
        _select('tab_usuarios',
            'id,usuario_nome,usuario_tipo,estado,cidade,plano_id,id_plano_atual,nome_plano_ativo,dt_cadastro,recorrente,plano_expiracao,plano_data_ativacao,usuario_status'),
        _select('tab_planos',
            'id,nome_plano,valor,valor_recorrente,status,tipo_usuario,recorrencia_ativa,google_ativo,limite_servicos,limite_fotos,qtde_postagem,qtde_videos,limite_dias,limite_dias_recorrente,limite_imagens_ia'),
        _select('tab_planos_manuais', '*'),
        _select('tab_assinaturas', '*'),
        _select('tab_assinaturas_google', '*'),
        _select('tab_pagamentos_recorrentes', '*'),
      ]);

      if (!mounted) return;
      setState(() {
        _usuarios = resultados[0];
        _planos = resultados[1];
        _manuais = resultados[2];
        _assinaturas = resultados[3];
        _google = resultados[4];
        _pagRec = resultados[5];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _escolherInicio() async {
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: _inicio,
      titulo: 'Data inicial',
    );
    if (d == null) return;
    setState(() {
      _inicio = d;
      if (_fim.isBefore(_inicio)) _fim = _inicio;
    });
  }

  Future<void> _escolherFim() async {
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: _fim,
      titulo: 'Data final',
    );
    if (d == null) return;
    setState(() {
      _fim = d;
      if (_inicio.isAfter(_fim)) _inicio = _fim;
    });
  }

  String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _moeda(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    final p = s.split(',');
    final chars = p[0].split('').reversed.toList();
    final out = <String>[];
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) out.add('.');
      out.add(chars[i]);
    }
    return 'R\$ ${out.reversed.join()},${p[1]}';
  }

  Map<String, dynamic>? _catalogoPorId(String id) {
    for (final p in _planos) {
      if (_s(p['id']) == id) return p;
    }
    return null;
  }

  String _nomePlanoUsuario(Map<String, dynamic> u) {
    final nome = _s(u['nome_plano_ativo']);
    if (nome.isNotEmpty) return nome;
    final id = _s(u['id_plano_atual']).isNotEmpty
        ? _s(u['id_plano_atual'])
        : _s(u['plano_id']);
    final p = _catalogoPorId(id);
    return p == null ? 'Sem plano identificado' : _s(p['nome_plano']);
  }

  List<Map<String, dynamic>> get _usuariosPeriodo {
    return _usuarios
        .where((u) => _noPeriodo(_dt(u['plano_data_ativacao'])))
        .toList();
  }

  Map<String, int> _distribuicaoAtual() {
    final m = <String, int>{};
    for (final u in _usuarios) {
      final nome = _nomePlanoUsuario(u);
      m[nome] = (m[nome] ?? 0) + 1;
    }
    return m;
  }

  Map<String, int> _adesoesPeriodo() {
    final m = <String, int>{};
    for (final u in _usuariosPeriodo) {
      final nome = _nomePlanoUsuario(u);
      m[nome] = (m[nome] ?? 0) + 1;
    }
    return m;
  }

  Map<String, int> _statusAssinaturas() {
    final m = <String, int>{};
    for (final a in _assinaturas) {
      if (!_noPeriodo(_dt(a['data_inicio'] ?? a['created_at']))) continue;
      final s = _s(a['status_assinatura']);
      final k = s.isEmpty ? 'Sem status' : s;
      m[k] = (m[k] ?? 0) + 1;
    }
    for (final a in _google) {
      if (!_noPeriodo(_dt(a['created_at']))) continue;
      final s = _s(a['status_assinatura']);
      final k = s.isEmpty ? 'Sem status' : 'Google • $s';
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  int get _totalAtual => _usuarios.length;

  int get _gratisAtual =>
      _usuarios.where((u) => _planoGratisNome(_nomePlanoUsuario(u))).length;

  int get _manualAtual =>
      _usuarios.where((u) => _planoManualNome(_nomePlanoUsuario(u))).length;

  int get _pagantesAtual =>
      math.max(0, _totalAtual - _gratisAtual - _manualAtual);

  int get _recorrentesAtual =>
      _usuarios.where((u) => _b(u['recorrente'])).length;

  int get _vencendo30 {
    final agora = DateTime.now();
    final limite = agora.add(const Duration(days: 30));
    return _usuarios.where((u) {
      final d = _dt(u['plano_expiracao']);
      return d != null && d.isAfter(agora) && !d.isAfter(limite);
    }).length;
  }

  int get _expirados {
    final agora = DateTime.now();
    return _usuarios.where((u) {
      final d = _dt(u['plano_expiracao']);
      return d != null && d.isBefore(agora);
    }).length;
  }

  int get _assinaturasAtivas {
    return _assinaturas
            .where((a) => _statusAtivo(a['status_assinatura']))
            .length +
        _google.where((a) => _statusAtivo(a['status_assinatura'])).length;
  }

  int get _cancelamentosPeriodo {
    int n = 0;
    for (final a in _assinaturas) {
      final d = _dt(a['cancelado_em']);
      if (_noPeriodo(d) ||
          (_noPeriodo(_dt(a['updated_at'])) &&
              _statusCancelado(a['status_assinatura']))) n++;
    }
    for (final a in _google) {
      final cancelDate =
          _dt(a['cancelado_em'] ?? a['data_cancelamento'] ?? a['updated_at']);
      if (_statusCancelado(a['status_assinatura']) && _noPeriodo(cancelDate))
        n++;
    }
    return n;
  }

  double get _mrr {
    double total = 0;
    for (final a in _assinaturas) {
      if (_statusAtivo(a['status_assinatura']))
        total += _n(a['valor_recorrente']);
    }
    // Para Google, usa valor apenas se houver campo financeiro no registro.
    for (final a in _google) {
      if (_statusAtivo(a['status_assinatura'])) {
        total += _n(a['valor_recorrente'] ?? a['valor']);
      }
    }
    return total;
  }

  double get _receitaRecPeriodo {
    double total = 0;
    for (final p in _pagRec) {
      final d =
          _dt(p['data_cobranca'] ?? p['data_pagamento'] ?? p['created_at']);
      if (!_noPeriodo(d)) continue;
      if (_statusPago(p['status']) || _statusPago(p['status_efi'])) {
        total += _n(p['valor_pago'] ?? p['valor']);
        total -= _n(p['valor_estornado']);
      }
    }
    return math.max(0, total);
  }

  int get _pagamentosRecPeriodo {
    return _pagRec.where((p) {
      final d =
          _dt(p['data_cobranca'] ?? p['data_pagamento'] ?? p['created_at']);
      return _noPeriodo(d);
    }).length;
  }

  int get _pagamentosRecPagos {
    return _pagRec.where((p) {
      final d =
          _dt(p['data_cobranca'] ?? p['data_pagamento'] ?? p['created_at']);
      return _noPeriodo(d) &&
          (_statusPago(p['status']) || _statusPago(p['status_efi']));
    }).length;
  }

  double _percent(int n, int total) => total == 0 ? 0 : n * 100 / total;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Métricas • Planos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _laranja))
          : _erro != null
              ? _erroWidget()
              : RefreshIndicator(
                  onRefresh: _carregar,
                  color: _laranja,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      _periodo(),
                      const SizedBox(height: 14),
                      _titulo('Visão atual'),
                      _gradeResumo(),
                      const SizedBox(height: 18),
                      _titulo('Distribuição atual por plano'),
                      _ranking(_distribuicaoAtual(), _totalAtual),
                      const SizedBox(height: 18),
                      _titulo('Movimentação no período'),
                      _movimentacao(),
                      const SizedBox(height: 18),
                      _titulo('Adesões por plano no período'),
                      _ranking(_adesoesPeriodo(), _usuariosPeriodo.length),
                      const SizedBox(height: 18),
                      _titulo('Assinaturas e recorrência'),
                      _assinaturasCard(),
                      const SizedBox(height: 18),
                      _titulo('Status das assinaturas iniciadas no período'),
                      _ranking(_statusAssinaturas(),
                          _statusAssinaturas().values.fold(0, (a, b) => a + b)),
                      const SizedBox(height: 18),
                      _titulo('Financeiro recorrente'),
                      _financeiro(),
                      const SizedBox(height: 18),
                      _titulo('Catálogo de planos'),
                      _catalogo(),
                      const SizedBox(height: 18),
                      _titulo('Planos manuais'),
                      _manuaisCard(),
                      const SizedBox(height: 18),
                      _observacao(),
                    ],
                  ),
                ),
    );
  }

  Widget _periodo() {
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Período de análise',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'O período afeta adesões, cancelamentos, status iniciados e pagamentos. A base atual de planos permanece como fotografia do momento.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _botaoData('Inicial', _data(_inicio), _escolherInicio),
              _botaoData('Final', _data(_fim), _escolherFim),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _inicio =
                      DateTime(DateTime.now().year, DateTime.now().month, 1);
                  _fim = DateTime.now();
                }),
                icon: const Icon(Icons.today, size: 18),
                label: const Text('Mês atual'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _borda)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botaoData(String titulo, String data, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month, size: 18),
      label: Text('$titulo: $data'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: _laranja),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }

  Widget _gradeResumo() {
    final itens = [
      ('Usuários', '$_totalAtual', Icons.people_alt_outlined),
      ('Pagantes', '$_pagantesAtual', Icons.workspace_premium_outlined),
      ('Grátis', '$_gratisAtual', Icons.person_outline),
      ('Manuais', '$_manualAtual', Icons.admin_panel_settings_outlined),
      ('Recorrentes', '$_recorrentesAtual', Icons.autorenew),
      ('Assinaturas ativas', '$_assinaturasAtivas', Icons.verified_outlined),
      ('Vencem em 30 dias', '$_vencendo30', Icons.event_outlined),
      ('Expirados', '$_expirados', Icons.event_busy_outlined),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final col = w >= 1050
          ? 4
          : w >= 650
              ? 3
              : 2;
      final largura = (w - (col - 1) * 10) / col;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: itens
            .map((e) => SizedBox(
                  width: largura,
                  child: _kpi(e.$1, e.$2, e.$3),
                ))
            .toList(),
      );
    });
  }

  Widget _kpi(String titulo, String valor, IconData icon) {
    return _box(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: _laranja.withOpacity(.14),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: _laranja),
          ),
          const SizedBox(width: 11),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(valor,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(titulo,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _movimentacao() {
    final total = _usuariosPeriodo.length;
    final recorr = _usuariosPeriodo.where((u) => _b(u['recorrente'])).length;
    final manuais = _usuariosPeriodo
        .where((u) => _planoManualNome(_nomePlanoUsuario(u)))
        .length;
    return _box(
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          _mini('Ativações/adesões', '$total'),
          _mini('Recorrentes ativados', '$recorr'),
          _mini('Planos manuais ativados', '$manuais'),
          _mini('Cancelamentos', '$_cancelamentosPeriodo'),
          _mini('Conversão da base atual',
              '${_percent(_pagantesAtual, _totalAtual).toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  Widget _assinaturasCard() {
    final efiAtivas =
        _assinaturas.where((a) => _statusAtivo(a['status_assinatura'])).length;
    final googleAtivas =
        _google.where((a) => _statusAtivo(a['status_assinatura'])).length;
    final googleRec = _google.where((a) => _b(a['recorrente'])).length;
    final googleAv = _google.where((a) => !_b(a['recorrente'])).length;
    return _box(
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          _mini('Assinaturas internas ativas', '$efiAtivas'),
          _mini('Google ativas', '$googleAtivas'),
          _mini('Google recorrentes', '$googleRec'),
          _mini('Google avulsas', '$googleAv'),
          _mini('Recorrentes na base', '$_recorrentesAtual'),
        ],
      ),
    );
  }

  Widget _financeiro() {
    final taxa = _pagamentosRecPeriodo == 0
        ? 0.0
        : _pagamentosRecPagos * 100 / _pagamentosRecPeriodo;
    return _box(
      child: Column(
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _mini('MRR atual estimado', _moeda(_mrr)),
              _mini(
                  'Receita recorrente no período', _moeda(_receitaRecPeriodo)),
              _mini('Cobranças no período', '$_pagamentosRecPeriodo'),
              _mini('Cobranças pagas', '$_pagamentosRecPagos'),
              _mini('Taxa de pagamento', '${taxa.toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'MRR considera assinaturas atualmente ativas e seus valores recorrentes registrados. Receita do período considera cobranças recorrentes com status de pagamento reconhecido e desconta estornos registrados.',
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ranking(Map<String, int> dados, int total) {
    final itens = dados.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (itens.isEmpty)
      return _vazio('Nenhum dado encontrado para esta análise.');
    final maxV = itens.first.value;
    return _box(
      child: Column(
        children: itens.map((e) {
          final pct = total == 0 ? 0.0 : e.value * 100 / total;
          final bar = maxV == 0 ? 0.0 : e.value / maxV;
          return Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600))),
                  Text('${e.value}  •  ${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white70)),
                ]),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: bar,
                    minHeight: 7,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation(_laranja),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _catalogo() {
    if (_planos.isEmpty) return _vazio('Nenhum plano cadastrado.');
    final planos = [..._planos]
      ..sort((a, b) => _n(a['valor']).compareTo(_n(b['valor'])));
    return Column(
      children: planos.map((p) {
        final id = _s(p['id']);
        final nome = _s(p['nome_plano']).isEmpty
            ? 'Plano sem nome'
            : _s(p['nome_plano']);
        final qtd = _usuarios.where((u) {
          final uid = _s(u['id_plano_atual']).isNotEmpty
              ? _s(u['id_plano_atual'])
              : _s(u['plano_id']);
          return uid == id ||
              _nomePlanoUsuario(u).toLowerCase() == nome.toLowerCase();
        }).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _box(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(nome,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800))),
                _chip(_s(p['status']).isEmpty ? 'Sem status' : _s(p['status'])),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 18, runSpacing: 10, children: [
                _campo('Usuários atuais', '$qtd'),
                _campo('Valor avulso', _moeda(_n(p['valor']))),
                _campo('Valor recorrente', _moeda(_n(p['valor_recorrente']))),
                _campo(
                    'Tipo de usuário',
                    _s(p['tipo_usuario']).isEmpty
                        ? 'Todos/Não informado'
                        : _s(p['tipo_usuario'])),
                _campo('Recorrência',
                    _b(p['recorrencia_ativa']) ? 'Ativa' : 'Não'),
                _campo('Google', _b(p['google_ativo']) ? 'Ativo' : 'Não'),
                _campo('Serviços', _s(p['limite_servicos'])),
                _campo('Fotos', _s(p['limite_fotos'])),
                _campo('Postagens', _s(p['qtde_postagem'])),
                _campo('Vídeos', _s(p['qtde_videos'])),
                _campo('Imagens IA', _s(p['limite_imagens_ia'])),
              ]),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _manuaisCard() {
    if (_manuais.isEmpty)
      return _vazio('Nenhum registro em tab_planos_manuais.');
    final dist = <String, int>{};
    for (final p in _manuais) {
      final nome =
          _s(p['nome_plano']).isEmpty ? 'Sem nome' : _s(p['nome_plano']);
      dist[nome] = (dist[nome] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ranking(dist, _manuais.length),
        const SizedBox(height: 10),
        _box(
          child: Text(
            'Registros manuais cadastrados: ${_manuais.length}. Na base atual, $_manualAtual usuário(s) estão apontando para Teste, Cortesia, Parceria ou Especial.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _observacao() {
    return _box(
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _laranja),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'As métricas usam os valores e status existentes no banco, sem fixar nomes dos planos comerciais. Teste, Cortesia, Parceria e Especial são tratados como planos manuais conforme a regra atual do Ache Obra. Indicadores históricos dependem dos registros existentes nas tabelas de assinaturas e pagamentos.',
              style: TextStyle(color: Colors.white70, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      );

  Widget _box({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borda),
        ),
        child: child,
      );

  Widget _mini(String titulo, String valor) => SizedBox(
        width: 180,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor,
              style: const TextStyle(
                  color: _laranja, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(titulo,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  Widget _campo(String titulo, String valor) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(valor.isEmpty ? '—' : valor,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: _laranja.withOpacity(.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: const TextStyle(
                color: _laranja, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _vazio(String texto) => _box(
        child: Text(texto, style: const TextStyle(color: Colors.white60)),
      );

  Widget _erroWidget() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline,
                color: Colors.orangeAccent, size: 48),
            const SizedBox(height: 12),
            const Text('Não foi possível carregar as métricas de planos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_erro ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _laranja, foregroundColor: Colors.white),
            ),
          ]),
        ),
      );
}
