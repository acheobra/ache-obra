import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasEngajamentoPage extends StatefulWidget {
  const MetricasEngajamentoPage({super.key});

  @override
  State<MetricasEngajamentoPage> createState() =>
      _MetricasEngajamentoPageState();
}

class _MetricasEngajamentoPageState extends State<MetricasEngajamentoPage> {
  static const _fundo = Color(0xFF1A2C42);
  static const _card = Color(0xFF101B2B);
  static const _laranja = Color(0xFFFF8C00);

  bool _carregando = true;
  String? _erro;
  late DateTime _inicio;
  late DateTime _fim;

  List<Map<String, dynamic>> _acessos = [];
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _conversas = [];
  List<Map<String, dynamic>> _mensagens = [];
  List<Map<String, dynamic>> _demandas = [];
  List<Map<String, dynamic>> _trabalhos = [];
  List<Map<String, dynamic>> _avaliacoes = [];
  List<Map<String, dynamic>> _orcamentos = [];
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _ia = [];

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _fim = agora;
    _inicio = agora.subtract(const Duration(days: 29));
    _carregar();
  }

  DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  String _txt(dynamic v) => (v ?? '').toString().trim();

  bool _noPeriodo(dynamic valor) {
    final d = _dt(valor);
    if (d == null) return false;
    return !d.isBefore(_inicio) && !d.isAfter(_fim);
  }

  Future<List<Map<String, dynamic>>> _buscar(
    String tabela,
    String colunas,
  ) async {
    final r = await Supabase.instance.client.from(tabela).select(colunas);
    return List<Map<String, dynamic>>.from(
      (r as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      // Consultas independentes: uma tabela vazia não impede as demais.
      final resultados = await Future.wait([
        _buscar(
          'tab_acessos',
          'id, usuario_id, sessao_id, data_hora_acesso, data_hora_saida, '
              'duracao_segundos, tipo_acesso, plataforma, origem, '
              'pagina_inicial, ultima_pagina, sessao_ativa',
        ),
        _buscar(
          'tab_usuarios',
          'id, usuario_tipo, cidade, estado, nome_plano_ativo, recorrente, '
              'dt_cadastro',
        ),
        _buscar('tab_conversas', '*'),
        _buscar('tab_mensagens', '*'),
        _buscar('tab_demandas_clientes', '*'),
        _buscar('tab_trabalhos_fotos', '*'),
        _buscar('tab_avaliacoes', '*'),
        _buscar('tab_orcamentos', '*'),
        _buscar('tab_pedidos', '*'),
        _buscar('tab_jisa_imagens_uso', '*'),
      ]);

      _acessos = resultados[0];
      _usuarios = resultados[1];
      _conversas = resultados[2];
      _mensagens = resultados[3];
      _demandas = resultados[4];
      _trabalhos = resultados[5];
      _avaliacoes = resultados[6];
      _orcamentos = resultados[7];
      _pedidos = resultados[8];
      _ia = resultados[9];

      if (mounted) setState(() => _carregando = false);
    } catch (e) {
      debugPrint('Erro nas métricas de engajamento: $e');
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _carregando = false;
        });
      }
    }
  }

  dynamic _primeiroCampo(
    Map<String, dynamic> row,
    List<String> candidatos,
  ) {
    for (final c in candidatos) {
      if (row.containsKey(c) && row[c] != null) return row[c];
    }
    return null;
  }

  List<Map<String, dynamic>> _filtrarData(
    List<Map<String, dynamic>> dados,
    List<String> campos,
  ) =>
      dados.where((r) => _noPeriodo(_primeiroCampo(r, campos))).toList();

  List<Map<String, dynamic>> get _acessosPeriodo =>
      _filtrarData(_acessos, ['data_hora_acesso']);

  List<Map<String, dynamic>> get _conversasPeriodo =>
      _filtrarData(_conversas, ['created_at', 'criado_em']);

  List<Map<String, dynamic>> get _mensagensPeriodo =>
      _filtrarData(_mensagens, ['created_at', 'criado_em', 'enviado_em']);

  List<Map<String, dynamic>> get _demandasPeriodo =>
      _filtrarData(_demandas, ['criado_em', 'created_at']);

  List<Map<String, dynamic>> get _trabalhosPeriodo =>
      _filtrarData(_trabalhos, ['created_at', 'criado_em']);

  List<Map<String, dynamic>> get _avaliacoesPeriodo =>
      _filtrarData(_avaliacoes, ['created_at', 'criado_em']);

  List<Map<String, dynamic>> get _orcamentosPeriodo =>
      _filtrarData(_orcamentos, ['created_at', 'criado_em', 'data_criacao']);

  List<Map<String, dynamic>> get _pedidosPeriodo =>
      _filtrarData(_pedidos, ['created_at', 'criado_em', 'data_pedido']);

  List<Map<String, dynamic>> get _iaPeriodo =>
      _filtrarData(_ia, ['criado_em', 'atualizado_em']);

  Set<String> get _usuariosAcessaram => _acessosPeriodo
      .map((e) => _txt(e['usuario_id']))
      .where((e) => e.isNotEmpty)
      .toSet();

  Set<String> get _sessoes => _acessosPeriodo
      .map((e) => _txt(e['sessao_id']))
      .where((e) => e.isNotEmpty)
      .toSet();

  int get _duracaoTotal => _acessosPeriodo.fold<int>(
        0,
        (s, e) => s + ((e['duracao_segundos'] as num?)?.toInt() ?? 0),
      );

  double get _duracaoMedia =>
      _sessoes.isEmpty ? 0 : _duracaoTotal / _sessoes.length;

  double get _acessosPorUsuario => _usuariosAcessaram.isEmpty
      ? 0
      : _acessosPeriodo.length / _usuariosAcessaram.length;

  Set<String> _usuariosDe(
    List<Map<String, dynamic>> dados,
    List<String> candidatos,
  ) {
    final ids = <String>{};
    for (final r in dados) {
      final v = _primeiroCampo(r, candidatos);
      if (v != null && _txt(v).isNotEmpty) ids.add(_txt(v));
    }
    return ids;
  }

  Set<String> get _usuariosInteragiram {
    final ids = <String>{};
    ids.addAll(_usuariosAcessaram);
    ids.addAll(_usuariosDe(
      _mensagensPeriodo,
      ['remetente_id', 'usuario_id', 'sender_id'],
    ));
    ids.addAll(_usuariosDe(
      _demandasPeriodo,
      ['cliente_id', 'usuario_id'],
    ));
    ids.addAll(_usuariosDe(
      _trabalhosPeriodo,
      ['usuario_id', 'profissional_id'],
    ));
    ids.addAll(_usuariosDe(
      _avaliacoesPeriodo,
      ['avaliador_id', 'usuario_id', 'cliente_id'],
    ));
    ids.addAll(_usuariosDe(
      _orcamentosPeriodo,
      ['usuario_id', 'cliente_id', 'profissional_id'],
    ));
    ids.addAll(_usuariosDe(
      _pedidosPeriodo,
      ['usuario_id', 'cliente_id'],
    ));
    ids.addAll(_usuariosDe(_iaPeriodo, ['usuario_id']));
    return ids;
  }

  Map<String, int> _agrupar(
    List<Map<String, dynamic>> dados,
    String campo, {
    String vazio = 'Não informado',
  }) {
    final m = <String, int>{};
    for (final r in dados) {
      final k = _txt(r[campo]).isEmpty ? vazio : _txt(r[campo]);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  Map<int, int> get _porHora {
    final m = <int, int>{};
    for (final r in _acessosPeriodo) {
      final d = _dt(r['data_hora_acesso']);
      if (d != null) m[d.hour] = (m[d.hour] ?? 0) + 1;
    }
    return m;
  }

  Map<int, int> get _porDiaSemana {
    final m = <int, int>{};
    for (final r in _acessosPeriodo) {
      final d = _dt(r['data_hora_acesso']);
      if (d != null) m[d.weekday] = (m[d.weekday] ?? 0) + 1;
    }
    return m;
  }

  Map<DateTime, Set<String>> get _ativosPorDia {
    final m = <DateTime, Set<String>>{};
    for (final r in _acessosPeriodo) {
      final d = _dt(r['data_hora_acesso']);
      final id = _txt(r['usuario_id']);
      if (d == null || id.isEmpty) continue;
      final dia = DateTime(d.year, d.month, d.day);
      m.putIfAbsent(dia, () => <String>{}).add(id);
    }
    return m;
  }

  double get _dauMedio {
    final dias = _ativosPorDia.values;
    if (dias.isEmpty) return 0;
    return dias.fold<int>(0, (s, e) => s + e.length) / dias.length;
  }

  int _ativosDesde(Duration periodo) {
    final limite = _fim.subtract(periodo);
    return _acessos
        .where((r) {
          final d = _dt(r['data_hora_acesso']);
          return d != null && !d.isBefore(limite) && !d.isAfter(_fim);
        })
        .map((r) => _txt(r['usuario_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  int get _wau => _ativosDesde(const Duration(days: 7));
  int get _mau => _ativosDesde(const Duration(days: 30));

  String _n(int v) {
    final s = v.toString();
    return s.replaceAllMapped(
      RegExp(r'(?=(\d{3})+(?!\d))'),
      (m) => '.',
    );
  }

  String _pct(num v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  String _duracao(num segundos) {
    final s = segundos.round();
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}min ${s % 60}s';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return '${h}h ${m}min';
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  Future<void> _selecionar(bool inicio) async {
    final escolhido = await SeletorDataMetricas.mostrarDataHora(
      context,
      dataHoraInicial: inicio ? _inicio : _fim,
      primeiraData: DateTime(2020, 1, 1),
      ultimaData: DateTime(DateTime.now().year + 5, 12, 31, 23, 59),
      titulo: inicio ? 'Data e horário inicial' : 'Data e horário final',
    );
    if (escolhido == null || !mounted) return;
    setState(() {
      if (inicio) {
        _inicio = escolhido;
        if (_fim.isBefore(_inicio)) _fim = _inicio;
      } else {
        _fim = escolhido;
        if (_inicio.isAfter(_fim)) _inicio = _fim;
      }
    });
  }

  void _atalho(Duration d) {
    final agora = DateTime.now();
    setState(() {
      _fim = agora;
      _inicio = agora.subtract(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text('Métricas de Engajamento'),
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
              _filtros(),
              if (_erro != null) ...[
                const SizedBox(height: 18),
                _erroBox(),
              ],
              const SizedBox(height: 18),
              _resumo(),
              const SizedBox(height: 18),
              _audiencia(),
              const SizedBox(height: 18),
              _atividadeMarketplace(),
              const SizedBox(height: 18),
              _comportamentoAcesso(),
              const SizedBox(height: 18),
              _segmentacaoAcessos(),
              const SizedBox(height: 18),
              _qualidade(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtros() => _painel(
        'Período da análise',
        'Todos os indicadores respeitam data e horário quando a tabela possui '
            'registro temporal compatível.',
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _selecionar(true),
              icon: const Icon(Icons.schedule),
              label: Text('Início: ${_fmt(_inicio)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _selecionar(false),
              icon: const Icon(Icons.schedule),
              label: Text('Fim: ${_fmt(_fim)}'),
            ),
            OutlinedButton(
              onPressed: () => _atalho(const Duration(hours: 24)),
              child: const Text('24 horas'),
            ),
            OutlinedButton(
              onPressed: () => _atalho(const Duration(days: 7)),
              child: const Text('7 dias'),
            ),
            OutlinedButton(
              onPressed: () => _atalho(const Duration(days: 30)),
              child: const Text('30 dias'),
            ),
            OutlinedButton(
              onPressed: () => _atalho(const Duration(days: 90)),
              child: const Text('90 dias'),
            ),
          ],
        ),
      );

  Widget _resumo() => _painel(
        'Resumo de Engajamento',
        'Visão geral do uso e das interações no período.',
        _grade([
          _Kpi('USUÁRIOS ENGAJADOS', _n(_usuariosInteragiram.length),
              'com alguma atividade', Icons.groups_outlined),
          _Kpi('USUÁRIOS COM ACESSO', _n(_usuariosAcessaram.length),
              'únicos em tab_acessos', Icons.person_outline),
          _Kpi('ACESSOS', _n(_acessosPeriodo.length), 'eventos de acesso',
              Icons.login),
          _Kpi('SESSÕES', _n(_sessoes.length), 'sessões únicas',
              Icons.timer_outlined),
          _Kpi(
            'ACESSOS / USUÁRIO',
            _acessosPorUsuario.toStringAsFixed(2).replaceAll('.', ','),
            'média no período',
            Icons.repeat,
          ),
          _Kpi('TEMPO MÉDIO', _duracao(_duracaoMedia), 'por sessão',
              Icons.timelapse),
          _Kpi('TEMPO TOTAL', _duracao(_duracaoTotal), 'uso registrado',
              Icons.av_timer),
          _Kpi('DAU MÉDIO', _dauMedio.toStringAsFixed(1).replaceAll('.', ','),
              'ativos/dia', Icons.today_outlined),
        ]),
      );

  Widget _audiencia() {
    final base = _usuarios.length;
    final eng = _usuariosInteragiram.length;
    final taxa = base == 0 ? 0.0 : eng * 100 / base;
    return _painel(
      'Audiência Ativa',
      'Indicadores de frequência e alcance da base.',
      _grade([
        _Kpi('WAU', _n(_wau), 'ativos nos 7 dias até o fim do período',
            Icons.date_range),
        _Kpi('MAU', _n(_mau), 'ativos nos 30 dias até o fim do período',
            Icons.calendar_month),
        _Kpi('BASE CADASTRADA', _n(base), 'usuários existentes',
            Icons.people_alt_outlined),
        _Kpi('TAXA DE ENGAJAMENTO', _pct(taxa), 'engajados / base cadastrada',
            Icons.insights),
      ]),
    );
  }

  Widget _atividadeMarketplace() => _painel(
        'Atividade dentro do Ache Obra',
        'Ações reais realizadas pelos usuários, além de simplesmente abrir o app.',
        _grade([
          _Kpi('CONVERSAS', _n(_conversasPeriodo.length), 'criadas no período',
              Icons.forum_outlined),
          _Kpi('MENSAGENS', _n(_mensagensPeriodo.length), 'enviadas no período',
              Icons.chat_bubble_outline),
          _Kpi('DEMANDAS', _n(_demandasPeriodo.length), 'publicadas',
              Icons.assignment_outlined),
          _Kpi('TRABALHOS / FOTOS', _n(_trabalhosPeriodo.length), 'publicações',
              Icons.photo_library_outlined),
          _Kpi('AVALIAÇÕES', _n(_avaliacoesPeriodo.length), 'registradas',
              Icons.star_outline),
          _Kpi('ORÇAMENTOS', _n(_orcamentosPeriodo.length), 'registrados',
              Icons.request_quote_outlined),
          _Kpi('PEDIDOS', _n(_pedidosPeriodo.length), 'registrados',
              Icons.shopping_bag_outlined),
          _Kpi(
            'IMAGENS IA',
            _n(_iaPeriodo.fold<int>(
                0, (s, e) => s + ((e['quantidade'] as num?)?.toInt() ?? 0))),
            'uso registrado pela Jisa',
            Icons.auto_awesome_outlined,
          ),
        ]),
      );

  Widget _comportamentoAcesso() {
    final horas = _porHora.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dias = _porDiaSemana.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    const nomes = {
      1: 'Segunda-feira',
      2: 'Terça-feira',
      3: 'Quarta-feira',
      4: 'Quinta-feira',
      5: 'Sexta-feira',
      6: 'Sábado',
      7: 'Domingo',
    };

    return _painel(
      'Comportamento de Acesso',
      'Quando os usuários utilizam o aplicativo.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grade([
            _Kpi(
              'HORÁRIO DE PICO',
              horas.isEmpty
                  ? '—'
                  : '${horas.first.key.toString().padLeft(2, '0')}:00',
              horas.isEmpty ? 'sem acessos' : '${horas.first.value} acessos',
              Icons.schedule,
            ),
            _Kpi(
              'DIA DE PICO',
              dias.isEmpty ? '—' : nomes[dias.first.key]!,
              dias.isEmpty ? 'sem acessos' : '${dias.first.value} acessos',
              Icons.calendar_today_outlined,
            ),
          ]),
          const SizedBox(height: 14),
          _ranking(
            'Acessos por horário',
            horas
                .map((e) =>
                    MapEntry('${e.key.toString().padLeft(2, '0')}:00', e.value))
                .toList(),
          ),
          const SizedBox(height: 14),
          _ranking(
            'Acessos por dia da semana',
            dias.map((e) => MapEntry(nomes[e.key]!, e.value)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _segmentacaoAcessos() => _painel(
        'Tecnologia e Origem dos Acessos',
        'Distribuição dinâmica dos registros existentes em tab_acessos.',
        Column(
          children: [
            _ranking(
              'Plataformas',
              (_agrupar(_acessosPeriodo, 'plataforma').entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))),
            ),
            const SizedBox(height: 14),
            _ranking(
              'Origens',
              (_agrupar(_acessosPeriodo, 'origem').entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))),
            ),
            const SizedBox(height: 14),
            _ranking(
              'Tipos de acesso',
              (_agrupar(_acessosPeriodo, 'tipo_acesso').entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))),
            ),
            const SizedBox(height: 14),
            _ranking(
              'Páginas iniciais',
              (_agrupar(_acessosPeriodo, 'pagina_inicial').entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))),
            ),
          ],
        ),
      );

  Widget _qualidade() => _painel(
        'Cobertura dos Dados',
        'Ajuda a identificar quais partes da métrica ainda dependem da '
            'instrumentação do Flutter.',
        _grade([
          _Kpi(
            'REGISTROS DE ACESSO',
            _n(_acessos.length),
            _acessos.isEmpty
                ? 'aguardando integração do Flutter'
                : 'tab_acessos já possui dados',
            Icons.storage_outlined,
          ),
          _Kpi(
            'SESSÕES COM DURAÇÃO',
            _n(_acessos.where((e) => e['duracao_segundos'] != null).length),
            'registros com duração',
            Icons.timer,
          ),
          _Kpi(
            'ACESSOS COM PLATAFORMA',
            _n(_acessos.where((e) => _txt(e['plataforma']).isNotEmpty).length),
            'registros identificados',
            Icons.devices,
          ),
          _Kpi(
            'ACESSOS COM ORIGEM',
            _n(_acessos.where((e) => _txt(e['origem']).isNotEmpty).length),
            'registros identificados',
            Icons.alt_route,
          ),
        ]),
      );

  Widget _ranking(String titulo, List<MapEntry<String, int>> itens) {
    final max = itens.isEmpty ? 0 : itens.first.value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (itens.isEmpty)
            const Text('Sem dados no período.',
                style: TextStyle(color: Colors.white54))
          else
            ...itens.take(24).map((e) {
              final p = max == 0 ? 0.0 : e.value / max;
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(color: Colors.white70)),
                        ),
                        Text(_n(e.value),
                            style: const TextStyle(
                                color: _laranja, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: p,
                      minHeight: 5,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(_laranja),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _grade(List<_Kpi> itens) => LayoutBuilder(
        builder: (context, c) {
          int cols = 4;
          if (c.maxWidth < 620) {
            cols = 1;
          } else if (c.maxWidth < 1000) {
            cols = 2;
          }
          const gap = 12.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children:
                itens.map((k) => SizedBox(width: w, child: _kpi(k))).toList(),
          );
        },
      );

  Widget _kpi(_Kpi k) => Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _fundo,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(k.icone, color: _laranja, size: 27),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.titulo,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  _carregando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _laranja),
                        )
                      : Text(k.valor,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(k.detalhe,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _painel(String titulo, String subtitulo, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    color: _laranja,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
            const SizedBox(height: 5),
            Text(subtitulo,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );

  Widget _erroBox() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(.5)),
        ),
        child: Text(
          'Não foi possível carregar todos os dados de engajamento.\n$_erro',
          style: const TextStyle(color: Colors.white70),
        ),
      );
}

class _Kpi {
  final String titulo;
  final String valor;
  final String detalhe;
  final IconData icone;

  const _Kpi(this.titulo, this.valor, this.detalhe, this.icone);
}
