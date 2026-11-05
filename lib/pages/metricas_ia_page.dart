import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasIAPage extends StatefulWidget {
  const MetricasIAPage({super.key});

  @override
  State<MetricasIAPage> createState() => _MetricasIAPageState();
}

class _MetricasIAPageState extends State<MetricasIAPage> {
  static const _bg = Color(0xFF1A2C42);
  static const _panel = Color(0xFF0F1C2C);
  static const _card = Color(0xFF1B3047);
  static const _border = Color(0xFF314A63);
  static const _orange = Color(0xFFFF8C00);
  static const _green = Color(0xFF12D67A);
  static const _red = Color(0xFFFF5252);
  static const _purple = Color(0xFF8D6CE6);
  static const _muted = Color(0xFFAAB4C0);

  final _db = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  DateTime? _inicio;
  DateTime? _fim;

  List<Map<String, dynamic>> _usos = [];
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _manuais = [];

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _fim = DateTime(h.year, h.month, h.day);
    _inicio = _fim!.subtract(const Duration(days: 29));
    _carregar();
  }

  Future<List<Map<String, dynamic>>> _paginar(
      String tabela, String campos) async {
    const lote = 1000;
    int ini = 0;
    final saida = <Map<String, dynamic>>[];
    while (true) {
      final r =
          await _db.from(tabela).select(campos).range(ini, ini + lote - 1);
      final dados = List<Map<String, dynamic>>.from(r);
      saida.addAll(dados);
      if (dados.length < lote) break;
      ini += lote;
    }
    return saida;
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await Future.wait([
        _paginar('tab_jisa_imagens_uso',
            'id,usuario_id,periodo,quantidade,criado_em,atualizado_em'),
        _paginar('tab_usuarios',
            'id,usuario_nome,cidade,estado,usuario_tipo,plano_id,id_plano_atual,nome_plano_ativo,recorrente,usuario_status'),
        _paginar('tab_planos',
            'id,nome_plano,valor,valor_recorrente,tipo_usuario,status,recorrencia_ativa,limite_imagens_ia'),
        _paginar('tab_planos_manuais',
            'id,usuario_id,nome_plano,valor,tipo_usuario,status,ativo,limite_ia_mensal,limite_imagens_ia,data_inicio,data_fim'),
      ]);
      if (!mounted) return;
      setState(() {
        _usos = r[0];
        _usuarios = r[1];
        _planos = r[2];
        _manuais = r[3];
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

  DateTime? _dt(dynamic v) =>
      v == null ? null : (v is DateTime ? v : DateTime.tryParse(v.toString()));

  int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    var s = (v?.toString() ?? '').trim();
    if (s.contains(',') && s.contains('.'))
      s = s.replaceAll('.', '').replaceAll(',', '.');
    else if (s.contains(',')) s = s.replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }

  String _txt(dynamic v, [String padrao = 'Não informado']) {
    final s = (v?.toString() ?? '').trim();
    return s.isEmpty ? padrao : s;
  }

  String _norm(dynamic v) => (v?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  bool _manual(String? nome) =>
      const {'teste', 'cortesia', 'parceria', 'especial'}.contains(_norm(nome));

  bool _noPeriodo(DateTime? d) {
    if (d == null) return false;
    final x = DateTime(d.year, d.month, d.day);
    if (_inicio != null &&
        x.isBefore(DateTime(_inicio!.year, _inicio!.month, _inicio!.day)))
      return false;
    if (_fim != null && x.isAfter(DateTime(_fim!.year, _fim!.month, _fim!.day)))
      return false;
    return true;
  }

  List<Map<String, dynamic>> get _filtrados =>
      _usos.where((e) => _noPeriodo(_dt(e['periodo']))).toList();

  Map<String, Map<String, dynamic>> _porId(List<Map<String, dynamic>> lista) {
    final m = <String, Map<String, dynamic>>{};
    for (final e in lista) {
      final id = e['id']?.toString();
      if (id != null) m[id] = e;
    }
    return m;
  }

  Map<String, dynamic>? _usuario(Map<String, dynamic> uso) =>
      _porId(_usuarios)[uso['usuario_id']?.toString()];

  Map<String, dynamic>? _plano(Map<String, dynamic>? u) {
    if (u == null) return null;
    final nome = u['nome_plano_ativo']?.toString();
    final id = (u['id_plano_atual'] ?? u['plano_id'])?.toString();

    if (_manual(nome)) {
      final mapa = _porId(_manuais);
      if (id != null && mapa[id] != null) return mapa[id];
      final uid = u['id']?.toString();
      final c = _manuais
          .where((p) =>
              p['usuario_id']?.toString() == uid &&
              _norm(p['nome_plano']) == _norm(nome))
          .toList();
      if (c.isNotEmpty) return c.first;
      return null;
    }

    final mapa = _porId(_planos);
    if (id != null && mapa[id] != null) return mapa[id];
    for (final p in _planos) {
      if (_norm(p['nome_plano']) == _norm(nome)) return p;
    }
    return null;
  }

  int _limite(Map<String, dynamic>? u) => _int(_plano(u)?['limite_imagens_ia']);

  bool _pagante(Map<String, dynamic>? u) {
    if (u == null) return false;
    final nome = _norm(u['nome_plano_ativo']);
    if (nome.isEmpty || nome == 'gratis' || nome == 'gratuito') return false;
    final p = _plano(u);
    if (p == null) return !_manual(nome);
    return _num(p['valor']) > 0 || _num(p['valor_recorrente']) > 0;
  }

  int get _total => _filtrados.fold(0, (s, e) => s + _int(e['quantidade']));
  Set<String> get _ids => _filtrados
      .map((e) => e['usuario_id']?.toString())
      .whereType<String>()
      .toSet();
  double get _media => _ids.isEmpty ? 0 : _total / _ids.length;

  Map<String, int> _agrupar(String Function(Map<String, dynamic>) chave) {
    final m = <String, int>{};
    for (final e in _filtrados) {
      final k = chave(e);
      m[k] = (m[k] ?? 0) + _int(e['quantidade']);
    }
    return m;
  }

  Map<String, int> get _porPlano =>
      _agrupar((e) => _txt(_usuario(e)?['nome_plano_ativo']));
  Map<String, int> get _porTipo =>
      _agrupar((e) => _txt(_usuario(e)?['usuario_tipo']));
  Map<String, int> get _porEstado =>
      _agrupar((e) => _txt(_usuario(e)?['estado']));
  Map<String, int> get _porCidade => _agrupar((e) {
        final u = _usuario(e);
        final c = _txt(u?['cidade']);
        final uf = _txt(u?['estado'], '');
        return uf.isEmpty ? c : '$c/$uf';
      });

  Map<String, int> get _porDia {
    final m = <String, int>{};
    for (final e in _filtrados) {
      final d = _dt(e['periodo']);
      if (d == null) continue;
      final k = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      m[k] = (m[k] ?? 0) + _int(e['quantidade']);
    }
    return m;
  }

  int get _usoPagantes {
    int n = 0;
    for (final e in _filtrados) {
      if (_pagante(_usuario(e))) n += _int(e['quantidade']);
    }
    return n;
  }

  Map<String, int> get _consumoMes {
    final h = DateTime.now();
    final m = <String, int>{};
    for (final e in _usos) {
      final d = _dt(e['periodo']);
      if (d != null && d.year == h.year && d.month == h.month) {
        final id = e['usuario_id']?.toString();
        if (id != null) m[id] = (m[id] ?? 0) + _int(e['quantidade']);
      }
    }
    return m;
  }

  int get _proximos {
    int n = 0;
    final us = _porId(_usuarios);
    for (final e in _consumoMes.entries) {
      final l = _limite(us[e.key]);
      if (l > 0 && e.value / l >= .8 && e.value / l < 1) n++;
    }
    return n;
  }

  int get _noLimite {
    int n = 0;
    final us = _porId(_usuarios);
    for (final e in _consumoMes.entries) {
      final l = _limite(us[e.key]);
      if (l > 0 && e.value >= l) n++;
    }
    return n;
  }

  Future<void> _selecionar(bool inicial) async {
    final atual = inicial ? _inicio : _fim;
    final d = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: atual ?? DateTime.now(),
      titulo: inicial ? 'Data inicial' : 'Data final',
    );
    if (d == null || !mounted) return;
    setState(() {
      final x = DateTime(d.year, d.month, d.day);
      if (inicial) {
        _inicio = x;
        if (_fim != null && x.isAfter(_fim!)) _fim = x;
      } else {
        _fim = x;
        if (_inicio != null && x.isBefore(_inicio!)) _inicio = x;
      }
    });
  }

  void _dias(int n) {
    final h = DateTime.now();
    setState(() {
      _fim = DateTime(h.year, h.month, h.day);
      _inicio = _fim!.subtract(Duration(days: n - 1));
    });
  }

  String _data(DateTime? d) => d == null
      ? 'Todo período'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _n(num v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  Widget _painel(String titulo, String subtitulo, Widget filho) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: const TextStyle(
                  color: _orange, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(subtitulo, style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 18),
          filho,
        ]),
      );

  Widget _cardResumo(
          String titulo, String valor, String sub, IconData icone, Color cor) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(titulo.toUpperCase(),
                    style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 13),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(sub, style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
      );

  Widget _resumo() {
    final gratuitos = _total - _usoPagantes;
    final cards = [
      _cardResumo('Imagens geradas', _n(_total), 'no período selecionado',
          Icons.auto_awesome, _green),
      _cardResumo('Usuários da IA', _n(_ids.length), 'usuários únicos',
          Icons.people_alt_outlined, _orange),
      _cardResumo('Média por usuário', _n(_media), 'imagens por usuário',
          Icons.analytics_outlined, _purple),
      _cardResumo('Próximos do limite', _n(_proximos), '80% a 99% no mês atual',
          Icons.warning_amber_rounded, _orange),
      _cardResumo('No limite', _n(_noLimite), '100% ou mais no mês atual',
          Icons.block_outlined, _red),
      _cardResumo(
          'Uso pagantes',
          _n(_usoPagantes),
          _total == 0
              ? '0% do uso'
              : '${(_usoPagantes * 100 / _total).toStringAsFixed(1).replaceAll('.', ',')}% do uso',
          Icons.workspace_premium_outlined,
          _green),
      _cardResumo(
          'Uso gratuitos',
          _n(gratuitos),
          _total == 0
              ? '0% do uso'
              : '${(gratuitos * 100 / _total).toStringAsFixed(1).replaceAll('.', ',')}% do uso',
          Icons.person_outline,
          _orange),
      _cardResumo('Registros', _n(_filtrados.length), 'registros de consumo',
          Icons.storage_outlined, _purple),
    ];
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth < 700 ? 1 : (c.maxWidth < 1050 ? 2 : 4);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((x) => SizedBox(width: w, child: x)).toList());
    });
  }

  Widget _filtros() => Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: () => _selecionar(true),
            icon: const Icon(Icons.calendar_month, size: 17),
            label: Text('Data inicial: ${_data(_inicio)}')),
        OutlinedButton.icon(
            onPressed: () => _selecionar(false),
            icon: const Icon(Icons.calendar_month, size: 17),
            label: Text('Data final: ${_data(_fim)}')),
        for (final e in const [
          ('7 dias', 7),
          ('30 dias', 30),
          ('90 dias', 90),
          ('1 ano', 365)
        ])
          OutlinedButton(
              onPressed: () => _dias(e.$2),
              child: Text(e.$1, style: const TextStyle(color: _purple))),
        TextButton(
            onPressed: () => setState(() {
                  _inicio = null;
                  _fim = null;
                }),
            child:
                const Text('Todo o período', style: TextStyle(color: _purple))),
      ]);

  Widget _ranking(String titulo, Map<String, int> dados) {
    final lista = dados.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = lista.take(10).toList();
    final maximo = top.isEmpty ? 1 : math.max(1, top.first.value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        if (top.isEmpty)
          const Text('Sem dados no período.', style: TextStyle(color: _muted))
        else
          ...top.asMap().entries.map((x) {
            final e = x.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(children: [
                Row(children: [
                  SizedBox(
                      width: 30,
                      child: Text('${x.key + 1}º',
                          style: const TextStyle(
                              color: _orange, fontWeight: FontWeight.bold))),
                  Expanded(
                      child: Text(e.key,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white))),
                  Text(_n(e.value),
                      style: const TextStyle(
                          color: _green, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                    value: e.value / maximo,
                    minHeight: 5,
                    backgroundColor: _panel,
                    valueColor: const AlwaysStoppedAnimation(_orange)),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _duas(Widget a, Widget b) => LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 850) {
          return Column(children: [a, const SizedBox(height: 12), b]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]);
      });

  Widget _evolucao() {
    final dados = _porDia;
    final dias = dados.keys.toList()..sort();
    if (dias.isEmpty) {
      return const Text('Sem dados no período.',
          style: TextStyle(color: _muted));
    }
    final exibidos = dias.length > 31 ? dias.sublist(dias.length - 31) : dias;
    final maximo = exibidos.map((d) => dados[d] ?? 0).fold<int>(1, math.max);
    return SizedBox(
      height: 220,
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: exibidos.map((d) {
            final v = dados[d] ?? 0;
            return Expanded(
              child: Tooltip(
                message: '$d: $v imagens',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('$v',
                            style: const TextStyle(color: _muted, fontSize: 9)),
                        const SizedBox(height: 3),
                        Container(
                            height: 20 + 155 * v / maximo,
                            decoration: const BoxDecoration(
                                color: _orange,
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(4)))),
                      ]),
                ),
              ),
            );
          }).toList()),
    );
  }

  Widget _rankingUsuarios() {
    final porId = _agrupar((e) => e['usuario_id']?.toString() ?? '');
    final us = _porId(_usuarios);
    final m = <String, int>{};
    for (final e in porId.entries) {
      final nome = _txt(us[e.key]?['usuario_nome'], 'Usuário não identificado');
      m[nome] = (m[nome] ?? 0) + e.value;
    }
    return _ranking('Usuários com maior uso', m);
  }

  Widget _limites() {
    final us = _porId(_usuarios);
    final linhas = <Map<String, dynamic>>[];
    for (final e in _consumoMes.entries) {
      final u = us[e.key];
      final l = _limite(u);
      if (l <= 0) continue;
      linhas.add({
        'nome': _txt(u?['usuario_nome'], 'Usuário'),
        'plano': _txt(u?['nome_plano_ativo']),
        'uso': e.value,
        'limite': l,
        'p': e.value / l,
      });
    }
    linhas.sort((a, b) => (b['p'] as double).compareTo(a['p'] as double));
    if (linhas.isEmpty) {
      return const Text('Nenhum consumo com limite identificável no mês atual.',
          style: TextStyle(color: _muted));
    }
    return Column(
        children: linhas.take(15).map((x) {
      final p = x['p'] as double;
      final cor = p >= 1 ? _red : (p >= .8 ? _orange : _green);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border)),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text('${x['nome']} • ${x['plano']}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white))),
            Text('${x['uso']} / ${x['limite']}',
                style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 7),
          LinearProgressIndicator(
              value: p.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: _panel,
              valueColor: AlwaysStoppedAnimation(cor)),
          const SizedBox(height: 4),
          Align(
              alignment: Alignment.centerRight,
              child: Text(
                  '${(p * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
                  style: const TextStyle(color: _muted, fontSize: 11))),
        ]),
      );
    }).toList());
  }

  Widget _conteudo() => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          _painel(
              'Período da métrica',
              'Todos os indicadores de utilização são recalculados pelo período selecionado.',
              _filtros()),
          const SizedBox(height: 20),
          _painel(
              'Resumo de Inteligência Artificial',
              'Dados reais do controle de geração de imagens da JISA.',
              _resumo()),
          const SizedBox(height: 20),
          _painel(
              'Evolução do uso',
              'Imagens geradas por dia. Em períodos longos o gráfico mostra os 31 dias mais recentes.',
              _evolucao()),
          const SizedBox(height: 20),
          _painel(
              'Uso por perfil',
              'Distribuição conforme os dados atuais dos usuários.',
              _duas(_ranking('Uso por plano', _porPlano),
                  _ranking('Uso por tipo de usuário', _porTipo))),
          const SizedBox(height: 20),
          _painel(
              'Distribuição geográfica',
              'Localização atual cadastrada no perfil dos usuários.',
              _duas(_ranking('Uso por estado', _porEstado),
                  _ranking('Uso por cidade', _porCidade))),
          const SizedBox(height: 20),
          _painel(
              'Ranking de utilização',
              'Usuários com maior quantidade de imagens geradas no período.',
              _rankingUsuarios()),
          const SizedBox(height: 20),
          _painel(
              'Consumo dos limites',
              'Mês atual comparado ao limite_imagens_ia do plano do usuário.',
              _limites()),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border)),
            child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: _orange),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text(
                    'O banco atual registra especificamente o consumo de imagens da JISA. '
                    'Por isso esta tela não inventa métricas de mensagens de texto, tokens, '
                    'modelo GPT, custo OpenAI, tempo de resposta ou erros de IA. Esses '
                    'indicadores poderão ser adicionados quando houver registro próprio '
                    'dos eventos de IA.',
                    style: TextStyle(color: _muted, height: 1.45),
                  )),
                ]),
          ),
          const SizedBox(height: 24),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _panel,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Métricas de IA'),
          actions: [
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregando ? null : _carregar,
                icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
          ],
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator(color: _orange))
            : _erro != null
                ? Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 760),
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _red)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: _red, size: 38),
                        const SizedBox(height: 10),
                        const Text(
                            'Não foi possível carregar as métricas de IA.',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17)),
                        const SizedBox(height: 8),
                        SelectableText(_erro!,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: _muted, fontSize: 12)),
                        const SizedBox(height: 15),
                        ElevatedButton.icon(
                            onPressed: _carregar,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _orange,
                                foregroundColor: Colors.white)),
                      ]),
                    ),
                  )
                : _conteudo(),
      );
}
