import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/seletor_data_metricas.dart';

class MetricasUsuariosPage extends StatefulWidget {
  const MetricasUsuariosPage({super.key});

  @override
  State<MetricasUsuariosPage> createState() => _MetricasUsuariosPageState();
}

class _MetricasUsuariosPageState extends State<MetricasUsuariosPage> {
  static const Color _fundo = Color(0xFF1A2C42);

  static const Color _card = Color(0xFF101B2B);

  static const Color _laranja = Color(0xFFFF8C00);

  bool _carregando = true;

  String? _erro;

  DateTime? _dataInicial;

  DateTime? _dataFinal;

  List<Map<String, dynamic>> _todos = [];

  List<Map<String, dynamic>> _filtrados = [];

  String _normalizar(dynamic valor) {
    return (valor ?? '')
        .toString()
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
  }

  DateTime? _data(dynamic valor) {
    if (valor == null) return null;

    return DateTime.tryParse(valor.toString().trim());
  }

  @override
  void initState() {
    super.initState();

    _carregar();
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
                'id, usuario_tipo, usuario_status, bloqueado, '
                'nome_plano_ativo, recorrente, dt_cadastro',
              );

      _todos = List<Map<String, dynamic>>.from(
        (response as List).map((e) => Map<String, dynamic>.from(e)),
      );

      _aplicarFiltro();
    } catch (e) {
      debugPrint('Erro em métricas de usuários: $e');

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

  void _limparPeriodo() {
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

  int _tipo(String tipo) => _filtrados
      .where((u) => _normalizar(u['usuario_tipo']).contains(tipo))
      .length;

  int get _clientes => _tipo('cliente');

  int get _profissionais => _tipo('profissional');

  int get _arquitetos => _tipo('arquiteto');

  int get _engenheiros => _tipo('engenheiro');

  int get _bloqueados => _filtrados.where((u) {
        final s = _normalizar(u['usuario_status']);

        return u['bloqueado'] == true || s == 'bloqueado' || s == 'bloqueada';
      }).length;

  int get _inativos => _filtrados.where((u) {
        final s = _normalizar(u['usuario_status']);

        final bloqueado =
            u['bloqueado'] == true || s == 'bloqueado' || s == 'bloqueada';

        return !bloqueado && (s == 'inativo' || s == 'inativa');
      }).length;

  int get _ativos => _filtrados.where((u) {
        final s = _normalizar(u['usuario_status']);

        final bloqueado =
            u['bloqueado'] == true || s == 'bloqueado' || s == 'bloqueada';

        return !bloqueado && (s == 'ativo' || s == 'ativa' || s.isEmpty);
      }).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text('Métricas de Usuários'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filtroPeriodo(),
            const SizedBox(height: 22),
            if (_erro != null) _erroCard(),
            if (_erro != null) const SizedBox(height: 22),
            _secao(
              'Resumo',
              [
                _Item('TOTAL NO PERÍODO', _filtrados.length,
                    Icons.people_alt_outlined),
                _Item('CLIENTES', _clientes, Icons.person_outline),
                _Item('PROFISSIONAIS', _profissionais,
                    Icons.engineering_outlined),
                _Item('ARQUITETOS', _arquitetos, Icons.architecture_outlined),
                _Item('ENGENHEIROS', _engenheiros,
                    Icons.precision_manufacturing_outlined),
              ],
            ),
            const SizedBox(height: 22),
            _secao(
              'Status das Contas',
              [
                _Item('ATIVOS', _ativos, Icons.check_circle_outline),
                _Item('INATIVOS', _inativos, Icons.pause_circle_outline),
                _Item('BLOQUEADOS', _bloqueados, Icons.block_outlined),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtroPeriodo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Período de cadastro',
            style: TextStyle(
              color: _laranja,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _dataButton(
                  'Data inicial', _dataInicial, () => _selecionarData(true)),
              _dataButton(
                  'Data final', _dataFinal, () => _selecionarData(false)),
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
              TextButton(
                onPressed: _limparPeriodo,
                child: const Text('Todo o período'),
              ),
            ],
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
        'Erro ao carregar dados:\n$_erro',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _secao(String titulo, List<_Item> itens) {
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
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              int colunas = 4;

              if (constraints.maxWidth < 620) {
                colunas = 1;
              } else if (constraints.maxWidth < 1000) {
                colunas = 2;
              }

              const gap = 12.0;

              final largura =
                  (constraints.maxWidth - gap * (colunas - 1)) / colunas;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: itens
                    .map(
                      (i) => SizedBox(
                        width: largura,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _fundo,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Icon(i.icone, color: _laranja),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i.titulo,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _carregando
                                        ? const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _laranja,
                                          )
                                        : Text(
                                            i.valor.toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String titulo;

  final int valor;

  final IconData icone;

  const _Item(this.titulo, this.valor, this.icone);
}
