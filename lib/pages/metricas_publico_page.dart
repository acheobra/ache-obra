import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasPublicoPage extends StatefulWidget {
  const MetricasPublicoPage({super.key});

  @override
  State<MetricasPublicoPage> createState() => _MetricasPublicoPageState();
}

class _MetricasPublicoPageState extends State<MetricasPublicoPage> {
  static const Color _fundo = Color(0xFF1A2C42);
  static const Color _card = Color(0xFF101B2B);
  static const Color _laranja = Color(0xFFFF8C00);

  // Faixas centralizadas: se quiser alterar no futuro, basta editar aqui.
  static const List<_FaixaEtaria> _faixas = [
    _FaixaEtaria('Até 17 anos', 0, 17),
    _FaixaEtaria('18 a 24 anos', 18, 24),
    _FaixaEtaria('25 a 34 anos', 25, 34),
    _FaixaEtaria('35 a 44 anos', 35, 44),
    _FaixaEtaria('45 a 54 anos', 45, 54),
    _FaixaEtaria('55 a 64 anos', 55, 64),
    _FaixaEtaria('65 anos ou mais', 65, 150),
  ];

  bool _carregando = true;
  String? _erro;
  DateTime? _dataInicial;
  DateTime? _dataFinal;

  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _filtrados = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String _texto(dynamic valor) => (valor ?? '').toString().trim();

  String _normalizar(dynamic valor) => _texto(valor)
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

  DateTime? _data(dynamic valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString().trim());
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final response =
          await Supabase.instance.client.from('tab_usuarios').select(
                'id, usuario_tipo, genero, dt_nascimento, dt_cadastro',
              );

      _todos = List<Map<String, dynamic>>.from(
        (response as List).map((e) => Map<String, dynamic>.from(e)),
      );

      _aplicarFiltro();
    } catch (e) {
      debugPrint('Erro em métricas de público: $e');
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  void _aplicarFiltro() {
    final inicio = _dataInicial == null
        ? null
        : DateTime(_dataInicial!.year, _dataInicial!.month, _dataInicial!.day);

    final fim = _dataFinal == null
        ? null
        : DateTime(
            _dataFinal!.year,
            _dataFinal!.month,
            _dataFinal!.day,
            23,
            59,
            59,
            999,
          );

    final resultado = _todos.where((u) {
      if (inicio == null && fim == null) return true;
      final cadastro = _data(u['dt_cadastro']);
      if (cadastro == null) return false;
      if (inicio != null && cadastro.isBefore(inicio)) return false;
      if (fim != null && cadastro.isAfter(fim)) return false;
      return true;
    }).toList();

    if (!mounted) return;
    setState(() {
      _filtrados = resultado;
      _carregando = false;
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

  void _periodoRapido(int dias) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
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

  String _formatarData(DateTime? data) {
    if (data == null) return 'Selecionar';
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  String _numero(int valor) {
    final texto = valor.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < texto.length; i++) {
      final restante = texto.length - i;
      buffer.write(texto[i]);
      if (restante > 1 && restante % 3 == 1) buffer.write('.');
    }
    return buffer.toString();
  }

  String _percentual(int valor, [int? base]) {
    final total = base ?? _filtrados.length;
    if (total <= 0) return '0,00%';
    return '${((valor / total) * 100).toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  int? _idade(Map<String, dynamic> usuario) {
    final nascimento = _data(usuario['dt_nascimento']);
    if (nascimento == null) return null;

    final hoje = DateTime.now();
    if (nascimento.isAfter(hoje)) return null;

    int idade = hoje.year - nascimento.year;
    if (hoje.month < nascimento.month ||
        (hoje.month == nascimento.month && hoje.day < nascimento.day)) {
      idade--;
    }

    // Evita que datas evidentemente inválidas distorçam as métricas.
    if (idade < 0 || idade > 120) return null;
    return idade;
  }

  List<int> get _idadesValidas =>
      _filtrados.map(_idade).whereType<int>().toList();

  int get _comNascimento => _idadesValidas.length;
  int get _semNascimento => _filtrados.length - _comNascimento;

  double? get _idadeMedia {
    final idades = _idadesValidas;
    if (idades.isEmpty) return null;
    return idades.reduce((a, b) => a + b) / idades.length;
  }

  double? get _idadeMediana {
    final idades = [..._idadesValidas]..sort();
    if (idades.isEmpty) return null;
    final meio = idades.length ~/ 2;
    if (idades.length.isOdd) return idades[meio].toDouble();
    return (idades[meio - 1] + idades[meio]) / 2;
  }

  int? get _menorIdade {
    final idades = _idadesValidas;
    if (idades.isEmpty) return null;
    idades.sort();
    return idades.first;
  }

  int? get _maiorIdade {
    final idades = _idadesValidas;
    if (idades.isEmpty) return null;
    idades.sort();
    return idades.last;
  }

  Map<String, int> get _porFaixaEtaria {
    final mapa = <String, int>{};
    for (final faixa in _faixas) {
      mapa[faixa.rotulo] = 0;
    }

    for (final usuario in _filtrados) {
      final idade = _idade(usuario);
      if (idade == null) continue;
      for (final faixa in _faixas) {
        if (idade >= faixa.minimo && idade <= faixa.maximo) {
          mapa[faixa.rotulo] = (mapa[faixa.rotulo] ?? 0) + 1;
          break;
        }
      }
    }
    return mapa;
  }

  String _rotuloDinamico(dynamic valor, String vazio) {
    final original = _texto(valor);
    return original.isEmpty ? vazio : original;
  }

  Map<String, int> _agruparCampo(String campo, String vazio) {
    final grupos = <String, _Grupo>{};

    for (final usuario in _filtrados) {
      final original = _rotuloDinamico(usuario[campo], vazio);
      final chave = _normalizar(original);
      final existente = grupos[chave];

      if (existente == null) {
        grupos[chave] = _Grupo(original, 1);
      } else {
        existente.quantidade++;
      }
    }

    final resultado = <String, int>{};
    for (final grupo in grupos.values) {
      resultado[grupo.rotulo] = grupo.quantidade;
    }
    return resultado;
  }

  Map<String, int> get _porGenero => _agruparCampo('genero', 'Não informado');

  Map<String, int> get _porTipo =>
      _agruparCampo('usuario_tipo', 'Não informado');

  List<MapEntry<String, int>> _ranking(Map<String, int> mapa) {
    final lista = mapa.entries.toList();
    lista.sort((a, b) {
      final qtd = b.value.compareTo(a.value);
      if (qtd != 0) return qtd;
      return _normalizar(a.key).compareTo(_normalizar(b.key));
    });
    return lista;
  }

  String _faixaDoUsuario(Map<String, dynamic> usuario) {
    final idade = _idade(usuario);
    if (idade == null) return 'Idade não informada';
    for (final faixa in _faixas) {
      if (idade >= faixa.minimo && idade <= faixa.maximo) {
        return faixa.rotulo;
      }
    }
    return 'Idade não informada';
  }

  Map<String, Map<String, int>> _cruzamento(
    String Function(Map<String, dynamic>) linha,
    String Function(Map<String, dynamic>) coluna,
  ) {
    final resultado = <String, Map<String, int>>{};
    for (final usuario in _filtrados) {
      final l = linha(usuario);
      final c = coluna(usuario);
      resultado.putIfAbsent(l, () => <String, int>{});
      resultado[l]![c] = (resultado[l]![c] ?? 0) + 1;
    }
    return resultado;
  }

  String get _generoPrincipal {
    final lista = _ranking(_porGenero)
        .where((e) => _normalizar(e.key) != 'nao informado')
        .toList();
    return lista.isEmpty ? '—' : lista.first.key;
  }

  String get _tipoPrincipal {
    final lista = _ranking(_porTipo)
        .where((e) => _normalizar(e.key) != 'nao informado')
        .toList();
    return lista.isEmpty ? '—' : lista.first.key;
  }

  String get _faixaPrincipal {
    final lista = _ranking(_porFaixaEtaria).where((e) => e.value > 0).toList();
    return lista.isEmpty ? '—' : lista.first.key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text('Métricas de Público'),
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
              _filtroPeriodo(),
              const SizedBox(height: 22),
              if (_erro != null) ...[
                _erroCard(),
                const SizedBox(height: 22),
              ],
              _resumoPublico(),
              const SizedBox(height: 22),
              _qualidadeDados(),
              const SizedBox(height: 22),
              _perfilEtario(),
              const SizedBox(height: 22),
              _distribuicaoGenero(),
              const SizedBox(height: 22),
              _distribuicaoTipo(),
              const SizedBox(height: 22),
              _cruzamentoTipoGenero(),
              const SizedBox(height: 22),
              _cruzamentoTipoIdade(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtroPeriodo() {
    return _painel(
      titulo: 'Período de cadastro',
      subtitulo:
          'Filtra o público pela data em que cada usuário se cadastrou no Ache Obra.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _dataButton(
            'Data inicial',
            _dataInicial,
            () => _selecionarData(true),
          ),
          _dataButton(
            'Data final',
            _dataFinal,
            () => _selecionarData(false),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(7),
            child: const Text('7 dias'),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(30),
            child: const Text('30 dias'),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(90),
            child: const Text('90 dias'),
          ),
          OutlinedButton(
            onPressed: () => _periodoRapido(365),
            child: const Text('1 ano'),
          ),
          TextButton(
            onPressed: _todoPeriodo,
            child: const Text('Todo o período'),
          ),
        ],
      ),
    );
  }

  Widget _dataButton(String label, DateTime? data, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$label: ${_formatarData(data)}'),
      style: OutlinedButton.styleFrom(foregroundColor: _laranja),
    );
  }

  Widget _resumoPublico() {
    return _painel(
      titulo: 'Resumo do Público',
      subtitulo:
          'Principais características do público dentro do período selecionado.',
      child: _gradeIndicadores([
        _Indicador(
          'PÚBLICO ANALISADO',
          _numero(_filtrados.length),
          Icons.groups_2_outlined,
          'usuários no período',
        ),
        _Indicador(
          'IDADE MÉDIA',
          _idadeMedia == null
              ? '—'
              : '${_idadeMedia!.toStringAsFixed(1).replaceAll('.', ',')} anos',
          Icons.cake_outlined,
          '${_numero(_comNascimento)} com idade válida',
        ),
        _Indicador(
          'FAIXA PRINCIPAL',
          _faixaPrincipal,
          Icons.bar_chart_outlined,
          'maior grupo etário',
        ),
        _Indicador(
          'TIPO PRINCIPAL',
          _tipoPrincipal,
          Icons.badge_outlined,
          'maior perfil de usuário',
        ),
        _Indicador(
          'GÊNERO PRINCIPAL',
          _generoPrincipal,
          Icons.people_outline,
          'maior grupo informado',
        ),
      ]),
    );
  }

  Widget _qualidadeDados() {
    final generoInformado =
        _filtrados.where((u) => _texto(u['genero']).isNotEmpty).length;
    final tipoInformado =
        _filtrados.where((u) => _texto(u['usuario_tipo']).isNotEmpty).length;
    final perfilCompleto = _filtrados.where((u) {
      return _idade(u) != null &&
          _texto(u['genero']).isNotEmpty &&
          _texto(u['usuario_tipo']).isNotEmpty;
    }).length;

    return _painel(
      titulo: 'Qualidade dos Dados do Público',
      subtitulo:
          'Mostra quanto da base possui informações suficientes para segmentação.',
      child: _gradeIndicadores([
        _Indicador(
          'COM NASCIMENTO VÁLIDO',
          _numero(_comNascimento),
          Icons.event_available_outlined,
          _percentual(_comNascimento),
        ),
        _Indicador(
          'SEM NASCIMENTO VÁLIDO',
          _numero(_semNascimento),
          Icons.event_busy_outlined,
          _percentual(_semNascimento),
        ),
        _Indicador(
          'GÊNERO INFORMADO',
          _numero(generoInformado),
          Icons.person_search_outlined,
          _percentual(generoInformado),
        ),
        _Indicador(
          'TIPO INFORMADO',
          _numero(tipoInformado),
          Icons.assignment_ind_outlined,
          _percentual(tipoInformado),
        ),
        _Indicador(
          'PERFIL COMPLETO',
          _numero(perfilCompleto),
          Icons.fact_check_outlined,
          _percentual(perfilCompleto),
        ),
      ]),
    );
  }

  Widget _perfilEtario() {
    final faixas = _porFaixaEtaria;
    return _painel(
      titulo: 'Perfil Etário',
      subtitulo:
          'Idade calculada pela data de nascimento. Datas inválidas não entram nos cálculos de idade.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _gradeIndicadores([
            _Indicador(
              'IDADE MÉDIA',
              _idadeMedia == null
                  ? '—'
                  : _idadeMedia!.toStringAsFixed(1).replaceAll('.', ','),
              Icons.calculate_outlined,
              'anos',
            ),
            _Indicador(
              'IDADE MEDIANA',
              _idadeMediana == null
                  ? '—'
                  : _idadeMediana!.toStringAsFixed(1).replaceAll('.', ','),
              Icons.horizontal_rule,
              'anos',
            ),
            _Indicador(
              'MENOR IDADE',
              _menorIdade?.toString() ?? '—',
              Icons.arrow_downward,
              'idade válida',
            ),
            _Indicador(
              'MAIOR IDADE',
              _maiorIdade?.toString() ?? '—',
              Icons.arrow_upward,
              'idade válida',
            ),
          ]),
          const SizedBox(height: 18),
          ..._ranking(faixas).map(
            (e) => _barraDistribuicao(
              e.key,
              e.value,
              _comNascimento,
            ),
          ),
        ],
      ),
    );
  }

  Widget _distribuicaoGenero() {
    final lista = _ranking(_porGenero);
    return _painel(
      titulo: 'Distribuição por Gênero',
      subtitulo:
          'Categorias obtidas diretamente dos valores existentes em tab_usuarios.genero.',
      child: lista.isEmpty
          ? _vazio('Nenhum dado de gênero encontrado.')
          : Column(
              children: lista
                  .map(
                    (e) => _barraDistribuicao(
                      e.key,
                      e.value,
                      _filtrados.length,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _distribuicaoTipo() {
    final lista = _ranking(_porTipo);
    return _painel(
      titulo: 'Distribuição por Tipo de Usuário',
      subtitulo:
          'Clientes, profissionais e demais perfis são lidos dinamicamente do banco.',
      child: lista.isEmpty
          ? _vazio('Nenhum tipo de usuário encontrado.')
          : Column(
              children: lista
                  .map(
                    (e) => _barraDistribuicao(
                      e.key,
                      e.value,
                      _filtrados.length,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _cruzamentoTipoGenero() {
    final dados = _cruzamento(
      (u) => _rotuloDinamico(u['usuario_tipo'], 'Não informado'),
      (u) => _rotuloDinamico(u['genero'], 'Não informado'),
    );

    return _painel(
      titulo: 'Tipo de Usuário × Gênero',
      subtitulo:
          'Ajuda a entender a composição de gênero dentro de cada perfil de usuário.',
      child: _tabelaCruzamento(dados),
    );
  }

  Widget _cruzamentoTipoIdade() {
    final dados = _cruzamento(
      (u) => _rotuloDinamico(u['usuario_tipo'], 'Não informado'),
      _faixaDoUsuario,
    );

    return _painel(
      titulo: 'Tipo de Usuário × Faixa Etária',
      subtitulo:
          'Mostra quais faixas de idade estão presentes em cada tipo de usuário.',
      child: _tabelaCruzamento(dados),
    );
  }

  Widget _tabelaCruzamento(Map<String, Map<String, int>> dados) {
    if (dados.isEmpty) return _vazio('Nenhum dado disponível.');

    final linhas = dados.keys.toList()
      ..sort((a, b) => _normalizar(a).compareTo(_normalizar(b)));

    final colunas = <String>{};
    for (final valores in dados.values) {
      colunas.addAll(valores.keys);
    }
    final colunasOrdenadas = colunas.toList()
      ..sort((a, b) => _normalizar(a).compareTo(_normalizar(b)));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(_fundo.withOpacity(.9)),
        dataRowColor: const WidgetStatePropertyAll(_card),
        border: TableBorder.all(color: Colors.white12),
        columns: [
          const DataColumn(
            label: Text(
              'PERFIL',
              style: TextStyle(
                color: _laranja,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...colunasOrdenadas.map(
            (c) => DataColumn(
              label: Text(
                c,
                style: const TextStyle(
                  color: _laranja,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const DataColumn(
            label: Text(
              'TOTAL',
              style: TextStyle(
                color: _laranja,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        rows: linhas.map((linha) {
          final valores = dados[linha]!;
          final totalLinha =
              valores.values.fold<int>(0, (soma, valor) => soma + valor);

          return DataRow(
            cells: [
              DataCell(
                Text(
                  linha,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...colunasOrdenadas.map(
                (coluna) => DataCell(
                  Text(
                    _numero(valores[coluna] ?? 0),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              DataCell(
                Text(
                  _numero(totalLinha),
                  style: const TextStyle(
                    color: _laranja,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _barraDistribuicao(String titulo, int quantidade, int base) {
    final progresso = base <= 0 ? 0.0 : (quantidade / base).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _numero(quantidade),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                child: Text(
                  _percentual(quantidade, base),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: _laranja),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progresso,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(_laranja),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeIndicadores(List<_Indicador> itens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int colunas = 4;
        if (constraints.maxWidth < 620) {
          colunas = 1;
        } else if (constraints.maxWidth < 1000) {
          colunas = 2;
        }

        const gap = 12.0;
        final largura = (constraints.maxWidth - gap * (colunas - 1)) / colunas;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: itens.map((item) {
            return SizedBox(
              width: largura,
              child: Container(
                constraints: const BoxConstraints(minHeight: 116),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _fundo,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(item.icone, color: _laranja, size: 28),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.titulo,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _carregando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _laranja,
                                  ),
                                )
                              : Text(
                                  item.valor,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                          const SizedBox(height: 3),
                          Text(
                            item.detalhe,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _painel({
    required String titulo,
    required String subtitulo,
    required Widget child,
  }) {
    return Container(
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
          Text(
            titulo,
            style: const TextStyle(
              color: _laranja,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitulo,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _erroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(.5)),
      ),
      child: Text(
        'Não foi possível carregar as métricas de público.\n$_erro',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _vazio(String mensagem) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          mensagem,
          style: const TextStyle(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FaixaEtaria {
  final String rotulo;
  final int minimo;
  final int maximo;

  const _FaixaEtaria(this.rotulo, this.minimo, this.maximo);
}

class _Grupo {
  final String rotulo;
  int quantidade;

  _Grupo(this.rotulo, this.quantidade);
}

class _Indicador {
  final String titulo;
  final String valor;
  final IconData icone;
  final String detalhe;

  const _Indicador(
    this.titulo,
    this.valor,
    this.icone,
    this.detalhe,
  );
}
