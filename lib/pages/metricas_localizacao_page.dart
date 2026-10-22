import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasLocalizacaoPage extends StatefulWidget {
  const MetricasLocalizacaoPage({super.key});

  @override
  State<MetricasLocalizacaoPage> createState() =>
      _MetricasLocalizacaoPageState();
}

class _MetricasLocalizacaoPageState extends State<MetricasLocalizacaoPage> {
  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _card = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);

  bool _carregando = true;
  String? _erro;
  DateTime? _dataInicial;
  DateTime? _dataFinal;
  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _filtrados = [];
  String _buscaCidade = '';
  String _ordemCidade = 'usuarios';
  String _ordemEstado = 'usuarios';
  bool _todosEstados = false;
  bool _todasCidades = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String _texto(dynamic v) => (v ?? '').toString().trim();

  String _normalizar(dynamic v) => _texto(v)
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

  DateTime? _data(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString().trim());

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client
          .from('tab_usuarios')
          .select('id, cidade, estado, dt_cadastro');
      _todos = List<Map<String, dynamic>>.from(
        (r as List).map((e) => Map<String, dynamic>.from(e)),
      );
      _aplicarFiltro();
    } catch (e) {
      debugPrint('Erro em métricas de localização: $e');
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  void _aplicarFiltro() {
    final ini = _dataInicial == null
        ? null
        : DateTime(_dataInicial!.year, _dataInicial!.month, _dataInicial!.day);
    final fim = _dataFinal == null
        ? null
        : DateTime(_dataFinal!.year, _dataFinal!.month, _dataFinal!.day, 23, 59,
            59, 999);
    final lista = _todos.where((u) {
      if (ini == null && fim == null) return true;
      final d = _data(u['dt_cadastro']);
      if (d == null) return false;
      if (ini != null && d.isBefore(ini)) return false;
      if (fim != null && d.isAfter(fim)) return false;
      return true;
    }).toList();
    if (!mounted) return;
    setState(() {
      _filtrados = lista;
      _carregando = false;
      _todosEstados = false;
      _todasCidades = false;
    });
  }

  Future<void> _selecionarData(bool inicial) async {
    final agora = DateTime.now();
    final atual = inicial ? _dataInicial : _dataFinal;

    final escolhida = await SeletorDataMetricas.mostrar(
      context,
      dataInicial: atual ?? agora,
      primeiraData: DateTime(2020, 1, 1),
      ultimaData: DateTime(agora.year + 5, 12, 31),
      titulo: inicial ? 'Selecionar data inicial' : 'Selecionar data final',
    );

    if (escolhida == null || !mounted) return;

    setState(() {
      if (inicial) {
        _dataInicial = escolhida;
        if (_dataFinal != null && _dataFinal!.isBefore(escolhida)) {
          _dataFinal = escolhida;
        }
      } else {
        _dataFinal = escolhida;
        if (_dataInicial != null && _dataInicial!.isAfter(escolhida)) {
          _dataInicial = escolhida;
        }
      }
    });

    _aplicarFiltro();
  }

  void _periodo(int dias) {
    final n = DateTime.now();
    final hoje = DateTime(n.year, n.month, n.day);
    setState(() {
      _dataFinal = hoje;
      _dataInicial = hoje.subtract(Duration(days: dias - 1));
    });
    _aplicarFiltro();
  }

  void _todoPeriodo() {
    setState(() {
      _dataInicial = null;
      _dataFinal = null;
    });
    _aplicarFiltro();
  }

  String _fmtData(DateTime? d) => d == null
      ? 'Selecionar'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _numero(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final r = s.length - i;
      b.write(s[i]);
      if (r > 1 && r % 3 == 1) b.write('.');
    }
    return b.toString();
  }

  String _pct(int v, [int? total]) {
    final t = total ?? _filtrados.length;
    if (t <= 0) return '0,00%';
    return '${((v / t) * 100).toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  String _estado(dynamic v) => _texto(v).isEmpty ? 'Não informado' : _texto(v);
  String _cidade(dynamic v) => _texto(v).isEmpty ? 'Não informada' : _texto(v);

  Map<String, int> get _porEstado {
    final m = <String, int>{};
    for (final u in _filtrados) {
      final k = _estado(u['estado']);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  Map<String, int> get _porCidade {
    final m = <String, int>{};
    for (final u in _filtrados) {
      final k = '${_cidade(u['cidade'])}|${_estado(u['estado'])}';
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  List<MapEntry<String, int>> _ordenar(Map<String, int> m, String ordem) {
    final l = m.entries.toList();
    if (ordem == 'nome') {
      l.sort((a, b) => _normalizar(a.key).compareTo(_normalizar(b.key)));
    } else {
      l.sort((a, b) {
        final q = b.value.compareTo(a.value);
        return q != 0 ? q : _normalizar(a.key).compareTo(_normalizar(b.key));
      });
    }
    return l;
  }

  int get _estados => _filtrados
      .map((u) => _texto(u['estado']))
      .where((v) => v.isNotEmpty)
      .map(_normalizar)
      .toSet()
      .length;

  int get _cidades => _filtrados
      .where((u) =>
          _texto(u['cidade']).isNotEmpty && _texto(u['estado']).isNotEmpty)
      .map((u) => '${_normalizar(u['cidade'])}|${_normalizar(u['estado'])}')
      .toSet()
      .length;

  int get _semEstado =>
      _filtrados.where((u) => _texto(u['estado']).isEmpty).length;
  int get _semCidade =>
      _filtrados.where((u) => _texto(u['cidade']).isEmpty).length;
  int get _completo => _filtrados
      .where((u) =>
          _texto(u['cidade']).isNotEmpty && _texto(u['estado']).isNotEmpty)
      .length;

  int _somaTopCidades(int n) => _ordenar(_porCidade, 'usuarios')
      .where((e) => !e.key.startsWith('Não informada|'))
      .take(n)
      .fold(0, (s, e) => s + e.value);

  List<MapEntry<String, int>> get _estadosVisiveis {
    final l = _ordenar(_porEstado, _ordemEstado);
    return (_todosEstados || l.length <= 10) ? l : l.take(10).toList();
  }

  List<MapEntry<String, int>> get _cidadesFiltradas {
    var l = _ordenar(_porCidade, _ordemCidade);
    if (_buscaCidade.trim().isNotEmpty) {
      final b = _normalizar(_buscaCidade);
      l = l
          .where((e) => _normalizar(e.key.replaceAll('|', ' ')).contains(b))
          .toList();
    }
    return l;
  }

  List<MapEntry<String, int>> get _cidadesVisiveis {
    final l = _cidadesFiltradas;
    return (_todasCidades || l.length <= 15) ? l : l.take(15).toList();
  }

  @override
  Widget build(BuildContext context) {
    final top5 = _somaTopCidades(5);
    final top10 = _somaTopCidades(10);
    final foraTop10 = (_filtrados.length - top10).clamp(0, _filtrados.length);

    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text('Métricas de Localização'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _painel(
                'Período de cadastro',
                'Todos os indicadores são recalculados pelo período selecionado.',
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _botaoData('Data inicial', _dataInicial,
                      () => _selecionarData(true)),
                  _botaoData(
                      'Data final', _dataFinal, () => _selecionarData(false)),
                  OutlinedButton(
                      onPressed: () => _periodo(7),
                      child: const Text('7 dias')),
                  OutlinedButton(
                      onPressed: () => _periodo(30),
                      child: const Text('30 dias')),
                  OutlinedButton(
                      onPressed: () => _periodo(90),
                      child: const Text('90 dias')),
                  OutlinedButton(
                      onPressed: () => _periodo(365),
                      child: const Text('1 ano')),
                  TextButton(
                      onPressed: _todoPeriodo,
                      child: const Text('Todo o período')),
                ]),
              ),
              const SizedBox(height: 22),
              if (_erro != null) ...[_erroCard(), const SizedBox(height: 22)],
              _painel(
                'Resumo Geográfico',
                'Distribuição da base no período selecionado.',
                _grade([
                  _Indicador('USUÁRIOS NO PERÍODO', _numero(_filtrados.length),
                      Icons.people_alt_outlined, 'cadastros considerados'),
                  _Indicador('ESTADOS ALCANÇADOS', _numero(_estados),
                      Icons.map_outlined, 'com estado informado'),
                  _Indicador('CIDADES ALCANÇADAS', _numero(_cidades),
                      Icons.location_city_outlined, 'cidade + estado'),
                  _Indicador(
                      'LOCALIZAÇÃO COMPLETA',
                      _pct(_completo),
                      Icons.fact_check_outlined,
                      '${_numero(_completo)} usuários'),
                ]),
              ),
              const SizedBox(height: 22),
              _painel(
                'Qualidade dos Dados',
                'Identifica cadastros incompletos para melhorar campanhas regionais.',
                _grade([
                  _Indicador('SEM ESTADO', _numero(_semEstado),
                      Icons.warning_amber_outlined, _pct(_semEstado)),
                  _Indicador('SEM CIDADE', _numero(_semCidade),
                      Icons.wrong_location_outlined, _pct(_semCidade)),
                  _Indicador('COM CIDADE E ESTADO', _numero(_completo),
                      Icons.check_circle_outline, _pct(_completo)),
                ]),
              ),
              const SizedBox(height: 22),
              _painel(
                'Concentração Geográfica',
                'Mostra quanto da base está concentrada nas cidades com mais usuários.',
                _grade([
                  _Indicador('TOP 5 CIDADES', _pct(top5),
                      Icons.filter_5_outlined, '${_numero(top5)} usuários'),
                  _Indicador('TOP 10 CIDADES', _pct(top10),
                      Icons.leaderboard_outlined, '${_numero(top10)} usuários'),
                  _Indicador(
                      'FORA DO TOP 10',
                      _pct(foraTop10),
                      Icons.scatter_plot_outlined,
                      '${_numero(foraTop10)} usuários'),
                ]),
              ),
              const SizedBox(height: 22),
              _rankingEstados(),
              const SizedBox(height: 22),
              _rankingCidades(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botaoData(String label, DateTime? d, VoidCallback f) =>
      OutlinedButton.icon(
        onPressed: f,
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text('$label: ${_fmtData(d)}'),
        style: OutlinedButton.styleFrom(foregroundColor: _laranja),
      );

  Widget _rankingEstados() {
    final todos = _ordenar(_porEstado, _ordemEstado);
    return _painel(
      'Usuários por Estado',
      'Ranking dinâmico conforme os dados cadastrados.',
      Column(children: [
        Align(
          alignment: Alignment.centerRight,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _ordemEstado,
              dropdownColor: _card,
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: _laranja,
              items: const [
                DropdownMenuItem(
                    value: 'usuarios', child: Text('Mais usuários')),
                DropdownMenuItem(value: 'nome', child: Text('Nome A-Z')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _ordemEstado = v);
              },
            ),
          ),
        ),
        if (_carregando)
          const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: _laranja))
        else if (todos.isEmpty)
          _vazio('Nenhum estado encontrado.')
        else
          ..._estadosVisiveis
              .asMap()
              .entries
              .map((e) => _linha(e.key + 1, e.value.key, null, e.value.value)),
        if (!_todosEstados && todos.length > 10)
          TextButton.icon(
            onPressed: () => setState(() => _todosEstados = true),
            icon: const Icon(Icons.expand_more),
            label: Text('Ver todos os ${todos.length} estados'),
          )
        else if (_todosEstados && todos.length > 10)
          TextButton.icon(
            onPressed: () => setState(() => _todosEstados = false),
            icon: const Icon(Icons.expand_less),
            label: const Text('Mostrar menos'),
          ),
      ]),
    );
  }

  Widget _rankingCidades() {
    final total = _cidadesFiltradas.length;
    return _painel(
      'Usuários por Cidade',
      'Pesquise, ordene e consulte todas as cidades encontradas.',
      Column(children: [
        LayoutBuilder(builder: (context, c) {
          final busca = TextField(
            onChanged: (v) => setState(() {
              _buscaCidade = v;
              _todasCidades = false;
            }),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Pesquisar cidade ou estado',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: _laranja),
              filled: true,
              fillColor: _fundo,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _laranja),
              ),
            ),
          );
          final ordem = DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _ordemCidade,
              dropdownColor: _card,
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: _laranja,
              items: const [
                DropdownMenuItem(
                    value: 'usuarios', child: Text('Mais usuários')),
                DropdownMenuItem(value: 'nome', child: Text('Cidade A-Z')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _ordemCidade = v);
              },
            ),
          );
          return c.maxWidth < 650
              ? Column(children: [
                  busca,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: ordem)
                ])
              : Row(children: [
                  Expanded(child: busca),
                  const SizedBox(width: 16),
                  ordem
                ]);
        }),
        const SizedBox(height: 16),
        if (_carregando)
          const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: _laranja))
        else if (_cidadesVisiveis.isEmpty)
          _vazio('Nenhuma cidade encontrada para os filtros atuais.')
        else
          ..._cidadesVisiveis.asMap().entries.map((e) {
            final p = e.value.key.split('|');
            return _linha(
                e.key + 1, p[0], p.length > 1 ? p[1] : null, e.value.value);
          }),
        if (!_todasCidades && total > 15)
          TextButton.icon(
            onPressed: () => setState(() => _todasCidades = true),
            icon: const Icon(Icons.expand_more),
            label: Text('Ver todas as $total cidades'),
          )
        else if (_todasCidades && total > 15)
          TextButton.icon(
            onPressed: () => setState(() => _todasCidades = false),
            icon: const Icon(Icons.expand_less),
            label: const Text('Mostrar menos'),
          ),
      ]),
    );
  }

  Widget _linha(int pos, String titulo, String? sub, int qtd) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _fundo,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          SizedBox(
              width: 38,
              child: Text('$posº',
                  style: const TextStyle(
                      color: _laranja, fontWeight: FontWeight.bold))),
          const Icon(Icons.location_on_outlined,
              color: Colors.white38, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(titulo,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                if (sub != null && sub.isNotEmpty)
                  Text(sub,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
          Text(_numero(qtd),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(width: 14),
          SizedBox(
              width: 72,
              child: Text(_pct(qtd),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: _laranja))),
        ]),
      );

  Widget _grade(List<_Indicador> itens) => LayoutBuilder(builder: (context, c) {
        var cols = 4;
        if (c.maxWidth < 620)
          cols = 1;
        else if (c.maxWidth < 1000) cols = 2;
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: itens
              .map((i) => SizedBox(
                    width: w,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 112),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _fundo,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(children: [
                        Icon(i.icone, color: _laranja, size: 28),
                        const SizedBox(width: 13),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(i.titulo,
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            _carregando
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: _laranja))
                                : Text(i.valor,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(i.detalhe,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 10.5)),
                          ],
                        )),
                      ]),
                    ),
                  ))
              .toList(),
        );
      });

  Widget _painel(String titulo, String subtitulo, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: const TextStyle(
                  color: _laranja, fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 5),
          Text(subtitulo,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget _erroCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(.5)),
        ),
        child: Text(
            'Não foi possível carregar as métricas de localização.\n$_erro',
            style: const TextStyle(color: Colors.white70)),
      );

  Widget _vazio(String m) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text(m,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center)),
      );
}

class _Indicador {
  final String titulo;
  final String valor;
  final IconData icone;
  final String detalhe;
  const _Indicador(this.titulo, this.valor, this.icone, this.detalhe);
}
