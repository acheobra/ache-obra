import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasCancelamentosPage extends StatefulWidget {
  const MetricasCancelamentosPage({super.key});

  @override
  State<MetricasCancelamentosPage> createState() =>
      _MetricasCancelamentosPageState();
}

class _MetricasCancelamentosPageState extends State<MetricasCancelamentosPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _fundoEscuro = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);
  static const Color _card = Color(0xFF142338);

  bool _carregando = true;
  String? _erro;
  DateTime _inicio = DateTime(DateTime.now().year, 1, 1);
  DateTime _fim = DateTime.now();
  String _origem = 'Todas';

  List<Map<String, dynamic>> _assinaturas = [];
  List<Map<String, dynamic>> _assinaturasGoogle = [];
  List<Map<String, dynamic>> _pagamentosRecorrentes = [];
  List<Map<String, dynamic>> _pagamentosAvulsos = [];
  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _usuarios = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  DateTime? _data(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  String _norm(dynamic v) => (v ?? '').toString().trim().toLowerCase();

  bool _noPeriodo(DateTime? d) {
    if (d == null) return false;
    final ini = DateTime(_inicio.year, _inicio.month, _inicio.day);
    final fim = DateTime(_fim.year, _fim.month, _fim.day, 23, 59, 59, 999);
    return !d.isBefore(ini) && !d.isAfter(fim);
  }

  bool _statusCancelado(dynamic status) {
    final s = _norm(status);
    return s.contains('cancel') || s == 'canceled' || s == 'cancelled';
  }

  DateTime? _dataCancelamentoEfi(Map<String, dynamic> a) {
    return _data(a['cancelado_em']);
  }

  DateTime? _dataCancelamentoGoogle(Map<String, dynamic> a) {
    final cancelado = _data(a['cancelado_em']);
    if (cancelado != null) return cancelado;
    if (_statusCancelado(a['status_assinatura'])) return _data(a['updated_at']);
    return null;
  }

  bool _googleEhCancelamento(Map<String, dynamic> a) {
    if (_norm(a['tipo_compra']) != 'recorrente' && a['recorrente'] != true) {
      return false;
    }
    return a['cancelado_em'] != null ||
        _statusCancelado(a['status_assinatura']);
  }

  Future<void> _carregarDados() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final r = await Future.wait<dynamic>([
        _supabase.from('tab_assinaturas').select(),
        _supabase.from('tab_assinaturas_google').select(),
        _supabase.from('tab_pagamentos_recorrentes').select(),
        _supabase.from('tab_pagamentos_avulsos').select(),
        _supabase
            .from('tab_planos')
            .select('id, nome_plano, valor, valor_recorrente, tipo_usuario'),
        _supabase.from('tab_usuarios').select(
              'id, usuario_nome, cidade, estado, usuario_tipo, nome_plano_ativo, dt_cadastro, dt_nascimento, genero, recorrente, usuario_status',
            ),
      ]);

      if (!mounted) return;
      setState(() {
        _assinaturas = (r[0] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _assinaturasGoogle = (r[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _pagamentosRecorrentes = (r[2] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _pagamentosAvulsos = (r[3] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _planos = (r[4] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _usuarios = (r[5] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _carregando = false;
      });
    } catch (e, st) {
      debugPrint('Erro métricas cancelamentos: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  List<Map<String, dynamic>> get _cancelEfi => _assinaturas
      .where((a) =>
          a['cancelado_em'] != null || _statusCancelado(a['status_assinatura']))
      .where((a) => _noPeriodo(_dataCancelamentoEfi(a)))
      .toList();

  List<Map<String, dynamic>> get _cancelGoogle => _assinaturasGoogle
      .where(_googleEhCancelamento)
      .where((a) => _noPeriodo(_dataCancelamentoGoogle(a)))
      .toList();

  List<Map<String, dynamic>> get _efiExibidos =>
      _origem == 'Google' ? [] : _cancelEfi;

  List<Map<String, dynamic>> get _googleExibidos =>
      _origem == 'Efí' ? [] : _cancelGoogle;

  Map<String, dynamic>? _usuario(String? id) {
    if (id == null) return null;
    for (final u in _usuarios) {
      if ((u['id'] ?? '').toString() == id) return u;
    }
    return null;
  }

  Map<String, dynamic>? _plano(String? id) {
    if (id == null) return null;
    for (final p in _planos) {
      if ((p['id'] ?? '').toString() == id) return p;
    }
    return null;
  }

  String _nomePlano(String? id) =>
      (_plano(id)?['nome_plano'] ?? 'Plano não identificado').toString();

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtDin(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _fmtPct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  String _fmtDecimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _selecionarInicio() async {
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: _inicio,
      titulo: 'Data inicial',
    );
    if (d != null && mounted) {
      setState(() {
        _inicio = d;
        if (_fim.isBefore(_inicio)) _fim = _inicio;
      });
    }
  }

  Future<void> _selecionarFim() async {
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: _fim,
      titulo: 'Data final',
    );
    if (d != null && mounted) {
      setState(() {
        _fim = d;
        if (_fim.isBefore(_inicio)) _inicio = _fim;
      });
    }
  }

  void _ultimosDias(int dias) {
    final agora = DateTime.now();
    setState(() {
      _fim = agora;
      _inicio = agora.subtract(Duration(days: dias - 1));
    });
  }

  void _todoPeriodo() {
    final datas = <DateTime>[];
    for (final a in _assinaturas) {
      final d = _dataCancelamentoEfi(a);
      if (d != null) datas.add(d);
    }
    for (final a in _assinaturasGoogle) {
      final d = _dataCancelamentoGoogle(a);
      if (d != null) datas.add(d);
    }
    if (datas.isEmpty) return;
    datas.sort();
    setState(() {
      _inicio = datas.first;
      _fim = DateTime.now().isAfter(datas.last) ? DateTime.now() : datas.last;
    });
  }

  Map<String, int> _contar(Iterable<String> valores) {
    final m = <String, int>{};
    for (final raw in valores) {
      final v = raw.trim().isEmpty ? 'Não informado' : raw.trim();
      m[v] = (m[v] ?? 0) + 1;
    }
    return m;
  }

  List<MapEntry<String, int>> _ordenarContagem(Map<String, int> m) {
    final l = m.entries.toList();
    l.sort((a, b) => b.value.compareTo(a.value));
    return l;
  }

  String _categoriaMotivo(String? motivo) {
    final m = _norm(motivo);
    if (m.isEmpty) return 'Sem motivo informado';
    if (m.contains('primeira cobrança') ||
        m.contains('primeira cobranca') ||
        m.contains('não aprovada') ||
        m.contains('nao aprovada') ||
        m.contains('instituição financeira') ||
        m.contains('instituicao financeira')) {
      return 'Falha na primeira cobrança';
    }
    if (m.contains('troca') && m.contains('plano')) return 'Troca de plano';
    if (m.contains('inadimpl')) return 'Inadimplência';
    if (m.contains('recusa') || m.contains('negad'))
      return 'Pagamento recusado';
    if (m.contains('estorn') || m.contains('reembols'))
      return 'Estorno/Reembolso';
    if (m.contains('usuário') ||
        m.contains('usuario') ||
        m.contains('solicit')) {
      return 'Solicitação do usuário';
    }
    return 'Outros motivos';
  }

  String _faixaTempo(Map<String, dynamic> a, bool google) {
    final ini = _data(a['data_inicio']) ?? _data(a['created_at']);
    final fim = google ? _dataCancelamentoGoogle(a) : _dataCancelamentoEfi(a);
    if (ini == null || fim == null) return 'Não calculável';
    final dias = fim.difference(ini).inHours / 24.0;
    if (dias < 1) return 'Mesmo dia';
    if (dias <= 7) return '1 a 7 dias';
    if (dias <= 30) return '8 a 30 dias';
    if (dias <= 90) return '31 a 90 dias';
    return 'Mais de 90 dias';
  }

  double _diasAteCancelar(Map<String, dynamic> a, bool google) {
    final ini = _data(a['data_inicio']) ?? _data(a['created_at']);
    final fim = google ? _dataCancelamentoGoogle(a) : _dataCancelamentoEfi(a);
    if (ini == null || fim == null || fim.isBefore(ini)) return -1;
    return fim.difference(ini).inMinutes / 1440.0;
  }

  int _idade(Map<String, dynamic>? u) {
    final n = _data(u?['dt_nascimento']);
    if (n == null) return -1;
    final hoje = DateTime.now();
    var idade = hoje.year - n.year;
    if (hoje.month < n.month || (hoje.month == n.month && hoje.day < n.day))
      idade--;
    return idade;
  }

  String _faixaIdade(Map<String, dynamic>? u) {
    final i = _idade(u);
    if (i < 0) return 'Não informado';
    if (i < 18) return 'Até 17';
    if (i <= 24) return '18–24';
    if (i <= 34) return '25–34';
    if (i <= 44) return '35–44';
    if (i <= 54) return '45–54';
    return '55+';
  }

  List<String> get _usuariosCancelados {
    final ids = <String>{};
    for (final a in _efiExibidos) {
      final id = a['usuario_id']?.toString();
      if (id != null) ids.add(id);
    }
    for (final a in _googleExibidos) {
      final id = a['usuario_id']?.toString();
      if (id != null) ids.add(id);
    }
    return ids.toList();
  }

  int get _totalCancelamentos => _efiExibidos.length + _googleExibidos.length;

  double get _mrrPerdido {
    double total = 0;
    for (final a in _efiExibidos) {
      total += _num(a['valor_recorrente']);
    }
    for (final a in _googleExibidos) {
      final p = _plano(a['plano_id']?.toString());
      total += _num(p?['valor_recorrente']);
    }
    return total;
  }

  List<Map<String, dynamic>> get _estornosPeriodo =>
      _pagamentosRecorrentes.where((p) {
        final d = _data(p['data_estorno']);
        return d != null && _noPeriodo(d);
      }).toList();

  List<Map<String, dynamic>> get _recusasPeriodo =>
      _pagamentosRecorrentes.where((p) {
        final d = _data(p['data_recusa']);
        return d != null && _noPeriodo(d);
      }).toList();

  List<Map<String, dynamic>> get _estornosAvulsosPeriodo =>
      _pagamentosAvulsos.where((p) {
        final d = _data(p['estorno_concluido_em']);
        return d != null && _noPeriodo(d);
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundoEscuro,
        foregroundColor: Colors.white,
        title: const Text('Métricas • Cancelamentos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarDados,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: _laranja))
          : _erro != null
              ? _erroWidget()
              : RefreshIndicator(
                  onRefresh: _carregarDados,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      _cabecalho(),
                      const SizedBox(height: 18),
                      _filtros(),
                      const SizedBox(height: 24),
                      _secao('Visão geral', _visaoGeral()),
                      _secao('Evolução dos cancelamentos', _evolucao()),
                      _secao('Motivos dos cancelamentos', _motivos()),
                      _secao('Cancelamentos por plano', _porPlano()),
                      _secao('Impacto financeiro', _financeiro()),
                      _secao('Ciclo de vida até o cancelamento', _cicloVida()),
                      _secao('Falhas, recusas e inadimplência', _falhas()),
                      _secao('Perfil de quem cancelou', _perfil()),
                      _secao('Geografia dos cancelamentos', _geografia()),
                      _secao('Origem e situação do cancelamento', _origens()),
                      _secao('Qualidade dos dados', _qualidade()),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _erroWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text('Não foi possível carregar as métricas.',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            SelectableText(_erro!,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
                onPressed: _carregarDados,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Cancelamentos',
            style: TextStyle(
                color: _laranja, fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 6),
        Text(
          'Acompanhe cancelamentos de assinaturas, motivos, impacto financeiro, tempo de permanência, falhas de pagamento e perfil dos usuários.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
      ],
    );
  }

  Widget _filtros() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _fundoEscuro,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12)),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _botaoData('Data inicial', _inicio, _selecionarInicio),
          _botaoData('Data final', _fim, _selecionarFim),
          _atalho('7 dias', () => _ultimosDias(7)),
          _atalho('30 dias', () => _ultimosDias(30)),
          _atalho('90 dias', () => _ultimosDias(90)),
          _atalho('1 ano', () => _ultimosDias(365)),
          _atalho('Todo período', _todoPeriodo),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              value: _origem,
              dropdownColor: _fundoEscuro,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Origem'),
              items: const [
                DropdownMenuItem(
                    value: 'Todas', child: Text('Todas as origens')),
                DropdownMenuItem(value: 'Efí', child: Text('Efí')),
                DropdownMenuItem(value: 'Google', child: Text('Google Play')),
              ],
              onChanged: (v) => setState(() => _origem = v ?? 'Todas'),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      );

  Widget _botaoData(String titulo, DateTime data, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 190,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_month, color: _laranja, size: 18),
            const SizedBox(width: 8),
            Text(_fmtData(data), style: const TextStyle(color: Colors.white))
          ]),
        ]),
      ),
    );
  }

  Widget _atalho(String texto, VoidCallback onTap) => ActionChip(
        label: Text(texto),
        onPressed: onTap,
        backgroundColor: _card,
        side: const BorderSide(color: Colors.white12),
        labelStyle: const TextStyle(color: Colors.white),
      );

  Widget _secao(String titulo, Widget conteudo) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        conteudo,
      ]),
    );
  }

  Widget _visaoGeral() {
    final usuarios = _usuariosCancelados.length;
    final ticket =
        _totalCancelamentos == 0 ? 0.0 : _mrrPerdido / _totalCancelamentos;
    final comMotivo = _efiExibidos
        .where((e) => _norm(e['motivo_cancelamento']).isNotEmpty)
        .length;
    final semMotivo = _efiExibidos.length - comMotivo;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _metrica('Cancelamentos', '$_totalCancelamentos', Icons.cancel_outlined,
          'Eventos no período'),
      _metrica('Usuários únicos', '$usuarios', Icons.person_off_outlined,
          'Pessoas afetadas'),
      _metrica('Efí', '${_efiExibidos.length}', Icons.credit_card_off_outlined,
          'Assinaturas canceladas'),
      _metrica('Google Play', '${_googleExibidos.length}', Icons.shop_outlined,
          'Assinaturas recorrentes'),
      _metrica('MRR perdido estimado', _fmtDin(_mrrPerdido),
          Icons.trending_down, 'Soma mensal associada'),
      _metrica('Valor médio cancelado', _fmtDin(ticket),
          Icons.payments_outlined, 'MRR / cancelamentos'),
      _metrica('Com motivo', '$comMotivo', Icons.fact_check_outlined,
          'Efí com motivo registrado'),
      _metrica('Sem motivo', '$semMotivo', Icons.help_outline,
          'Efí sem motivo registrado'),
    ]);
  }

  Widget _evolucao() {
    final mapa = <String, int>{};
    void add(DateTime? d) {
      if (d == null) return;
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      mapa[k] = (mapa[k] ?? 0) + 1;
    }

    for (final a in _efiExibidos) add(_dataCancelamentoEfi(a));
    for (final a in _googleExibidos) add(_dataCancelamentoGoogle(a));
    final itens = mapa.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (itens.isEmpty)
      return _vazio('Nenhum cancelamento no período selecionado.');
    final max = itens.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return _painel(Column(
        children: itens.map((e) {
      final p = max == 0 ? 0.0 : e.value / max;
      final partes = e.key.split('-');
      final label = '${partes[1]}/${partes[0]}';
      return _barra(label, e.value, p);
    }).toList()));
  }

  Widget _motivos() {
    final motivos = <String>[];
    for (final a in _efiExibidos)
      motivos.add(_categoriaMotivo(a['motivo_cancelamento']?.toString()));
    for (final a in _googleExibidos)
      motivos.add('Google Play / status de assinatura');
    final itens = _ordenarContagem(_contar(motivos));
    if (itens.isEmpty) return _vazio('Sem motivos de cancelamento no período.');
    return _rankingContagem(itens, total: _totalCancelamentos);
  }

  Widget _porPlano() {
    final dados = <String, Map<String, dynamic>>{};
    void add(Map<String, dynamic> a, double valor) {
      final id = a['plano_id']?.toString();
      final nome = _nomePlano(id);
      final x = dados.putIfAbsent(
          nome, () => {'qtd': 0, 'usuarios': <String>{}, 'valor': 0.0});
      x['qtd'] = (x['qtd'] as int) + 1;
      final uid = a['usuario_id']?.toString();
      if (uid != null) (x['usuarios'] as Set<String>).add(uid);
      x['valor'] = (x['valor'] as double) + valor;
    }

    for (final a in _efiExibidos) add(a, _num(a['valor_recorrente']));
    for (final a in _googleExibidos) {
      final p = _plano(a['plano_id']?.toString());
      add(a, _num(p?['valor_recorrente']));
    }
    final itens = dados.entries.toList()
      ..sort(
          (a, b) => (b.value['qtd'] as int).compareTo(a.value['qtd'] as int));
    if (itens.isEmpty) return _vazio('Nenhum plano cancelado no período.');
    return _painel(Column(
        children: itens.map((e) {
      final v = e.value;
      return _linhaDetalhe(
        e.key,
        '${v['qtd']} cancelamento(s) • ${(v['usuarios'] as Set).length} usuário(s)',
        _fmtDin(v['valor'] as double),
      );
    }).toList()));
  }

  Widget _financeiro() {
    final estornoRec = _estornosPeriodo.fold<double>(
        0, (s, p) => s + _num(p['valor_estornado']));
    final estornoAv =
        _estornosAvulsosPeriodo.fold<double>(0, (s, p) => s + _num(p['valor']));
    final receitaAnterior = <String, double>{};
    for (final p in _pagamentosRecorrentes) {
      final uid = p['usuario_id']?.toString();
      if (uid == null ||
          !_usuariosCancelados.contains(uid) ||
          p['data_pagamento'] == null) continue;
      receitaAnterior[uid] = (receitaAnterior[uid] ?? 0) + _num(p['valor']);
    }
    final totalAnterior =
        receitaAnterior.values.fold<double>(0, (a, b) => a + b);
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _metrica('MRR perdido estimado', _fmtDin(_mrrPerdido),
          Icons.money_off_csred_outlined, 'Valor recorrente dos cancelamentos'),
      _metrica('Estornos recorrentes', _fmtDin(estornoRec),
          Icons.currency_exchange, '${_estornosPeriodo.length} registro(s)'),
      _metrica('Estornos avulsos', _fmtDin(estornoAv), Icons.undo,
          '${_estornosAvulsosPeriodo.length} registro(s)'),
      _metrica('Receita anterior', _fmtDin(totalAnterior), Icons.history,
          'Pagamentos conhecidos dos usuários cancelados'),
    ]);
  }

  Widget _cicloVida() {
    final faixas = <String>[];
    final dias = <double>[];
    for (final a in _efiExibidos) {
      faixas.add(_faixaTempo(a, false));
      final d = _diasAteCancelar(a, false);
      if (d >= 0) dias.add(d);
    }
    for (final a in _googleExibidos) {
      faixas.add(_faixaTempo(a, true));
      final d = _diasAteCancelar(a, true);
      if (d >= 0) dias.add(d);
    }
    final media =
        dias.isEmpty ? 0.0 : dias.reduce((a, b) => a + b) / dias.length;
    final contagem = _ordenarContagem(_contar(faixas));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _metrica('Tempo médio até cancelar', '${_fmtDecimal(media)} dias',
            Icons.schedule, 'Da ativação ao cancelamento'),
        _metrica(
            'Cancelados no mesmo dia',
            '${faixas.where((e) => e == 'Mesmo dia').length}',
            Icons.timer_off_outlined,
            'Menos de 24 horas'),
      ]),
      const SizedBox(height: 12),
      if (contagem.isNotEmpty) _rankingContagem(contagem, total: faixas.length),
    ]);
  }

  Widget _falhas() {
    final recusasLigadas = _recusasPeriodo
        .where((p) => _usuariosCancelados.contains(p['usuario_id']?.toString()))
        .toList();
    final inadimplentes = _efiExibidos
        .where((a) => a['data_inicio_inadimplencia'] != null)
        .length;
    final primeiraCobranca = _efiExibidos
        .where((a) =>
            _categoriaMotivo(a['motivo_cancelamento']?.toString()) ==
            'Falha na primeira cobrança')
        .length;
    final motivosRecusa = _ordenarContagem(_contar(recusasLigadas.map(
        (p) => (p['motivo_recusa'] ?? 'Sem motivo informado').toString())));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _metrica('Recusas no período', '${_recusasPeriodo.length}',
            Icons.credit_card_off, 'Cobranças recorrentes recusadas'),
        _metrica('Recusas de usuários cancelados', '${recusasLigadas.length}',
            Icons.link_off, 'Recusas ligadas aos cancelados'),
        _metrica('Falha na 1ª cobrança', '$primeiraCobranca',
            Icons.warning_amber, 'Classificado pelo motivo registrado'),
        _metrica('Com inadimplência registrada', '$inadimplentes',
            Icons.event_busy, 'Data de início de inadimplência'),
      ]),
      if (motivosRecusa.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Text('Motivos de recusa',
            style:
                TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _rankingContagem(motivosRecusa, total: recusasLigadas.length),
      ],
    ]);
  }

  Widget _perfil() {
    final us = _usuariosCancelados
        .map(_usuario)
        .whereType<Map<String, dynamic>>()
        .toList();
    if (us.isEmpty)
      return _vazio(
          'Não foi possível relacionar usuários aos cancelamentos do período.');
    final tipos = _ordenarContagem(_contar(
        us.map((u) => (u['usuario_tipo'] ?? 'Não informado').toString())));
    final generos = _ordenarContagem(
        _contar(us.map((u) => (u['genero'] ?? 'Não informado').toString())));
    final idades = _ordenarContagem(_contar(us.map(_faixaIdade)));
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _miniRanking('Tipo de usuário', tipos, us.length),
      _miniRanking('Gênero', generos, us.length),
      _miniRanking('Faixa etária', idades, us.length),
    ]);
  }

  Widget _geografia() {
    final us = _usuariosCancelados
        .map(_usuario)
        .whereType<Map<String, dynamic>>()
        .toList();
    if (us.isEmpty) return _vazio('Sem dados geográficos relacionados.');
    final estados = _ordenarContagem(
        _contar(us.map((u) => (u['estado'] ?? 'Não informado').toString())));
    final cidades = _ordenarContagem(
        _contar(us.map((u) => (u['cidade'] ?? 'Não informado').toString())));
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _miniRanking('Estados', estados.take(10).toList(), us.length),
      _miniRanking('Cidades', cidades.take(10).toList(), us.length),
    ]);
  }

  Widget _origens() {
    final googleStatus = _ordenarContagem(_contar(_googleExibidos
        .map((a) => (a['status_assinatura'] ?? 'Não informado').toString())));
    final efiStatus = _ordenarContagem(_contar(_efiExibidos.map((a) =>
        (a['ultimo_status_efi'] ?? a['status_assinatura'] ?? 'Não informado')
            .toString())));
    final autoRenovacaoDesligada =
        _googleExibidos.where((a) => a['auto_renovacao'] == false).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _metrica('Efí', '${_efiExibidos.length}',
            Icons.account_balance_wallet_outlined, 'Cancelamentos no gateway'),
        _metrica('Google Play', '${_googleExibidos.length}', Icons.android,
            'Assinaturas recorrentes canceladas'),
        _metrica('Google sem renovação', '$autoRenovacaoDesligada',
            Icons.autorenew, 'auto_renovacao = false'),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        if (efiStatus.isNotEmpty)
          _miniRanking('Status Efí', efiStatus, _efiExibidos.length),
        if (googleStatus.isNotEmpty)
          _miniRanking('Status Google', googleStatus, _googleExibidos.length),
      ]),
    ]);
  }

  Widget _qualidade() {
    final efiSemMotivo = _efiExibidos
        .where((a) => _norm(a['motivo_cancelamento']).isEmpty)
        .length;
    final semPlano = [..._efiExibidos, ..._googleExibidos]
        .where((a) => _plano(a['plano_id']?.toString()) == null)
        .length;
    final semUsuario = [..._efiExibidos, ..._googleExibidos]
        .where((a) => _usuario(a['usuario_id']?.toString()) == null)
        .length;
    final efiSemValor =
        _efiExibidos.where((a) => _num(a['valor_recorrente']) <= 0).length;
    final googleSemDataExp =
        _googleExibidos.where((a) => a['data_expiracao'] == null).length;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _metrica('Efí sem motivo', '$efiSemMotivo', Icons.help_outline,
          'Motivo de cancelamento vazio'),
      _metrica('Plano não relacionado', '$semPlano',
          Icons.layers_clear_outlined, 'Plano não encontrado no catálogo'),
      _metrica('Usuário não relacionado', '$semUsuario',
          Icons.person_search_outlined, 'Usuário não encontrado'),
      _metrica('Efí sem valor recorrente', '$efiSemValor',
          Icons.price_change_outlined, 'Valor zerado ou ausente'),
      _metrica('Google sem expiração', '$googleSemDataExp',
          Icons.date_range_outlined, 'Entre cancelamentos Google filtrados'),
    ]);
  }

  Widget _metrica(
      String titulo, String valor, IconData icone, String subtitulo) {
    return Container(
      width: 245,
      height: 126,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: _fundoEscuro,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icone, color: _laranja, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(titulo,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2))
        ]),
        const SizedBox(height: 9),
        Text(valor,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(subtitulo,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _painel(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _fundoEscuro,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: child,
      );

  Widget _barra(String label, int valor, double proporcao) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white70))),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: proporcao.clamp(0.0, 1.0),
                    minHeight: 9,
                    backgroundColor: Colors.white10,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(_laranja)))),
        const SizedBox(width: 12),
        SizedBox(
            width: 45,
            child: Text('$valor',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _rankingContagem(List<MapEntry<String, int>> itens,
      {required int total}) {
    return _painel(Column(
        children: itens.map((e) {
      final pct = total == 0 ? 0.0 : e.value * 100 / total;
      return _linhaDetalhe(e.key, '${e.value} registro(s)', _fmtPct(pct));
    }).toList()));
  }

  Widget _miniRanking(
      String titulo, List<MapEntry<String, int>> itens, int total) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _fundoEscuro,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            style:
                const TextStyle(color: _laranja, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (itens.isEmpty)
          const Text('Sem dados', style: TextStyle(color: Colors.white54)),
        ...itens.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(color: Colors.white70),
                        overflow: TextOverflow.ellipsis)),
                Text(
                    '${e.value}  (${_fmtPct(total == 0 ? 0 : e.value * 100 / total)})',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            )),
      ]),
    );
  }

  Widget _linhaDetalhe(String titulo, String subtitulo, String direita) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitulo,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        const SizedBox(width: 12),
        Text(direita,
            style:
                const TextStyle(color: _laranja, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _vazio(String texto) => _painel(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: Text(texto, style: const TextStyle(color: Colors.white54))),
      ));
}
