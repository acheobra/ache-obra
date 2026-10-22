import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Painel administrativo das notificações internas do Ache Obra.

/// Configurações e campanhas persistidas no Supabase.

/// A publicação efetiva para destinatários depende de um executor backend.

class NotificacoesInternasPage extends StatefulWidget {
  const NotificacoesInternasPage({super.key});

  @override
  State<NotificacoesInternasPage> createState() =>
      _NotificacoesInternasPageState();
}

class _NotificacoesInternasPageState extends State<NotificacoesInternasPage> {
  static const _fundo = Color(0xFF1A2C42);

  static const _painel = Color(0xFF101B2B);

  static const _laranja = Color(0xFFFF8C00);

  static const _vermelho = Color(0xFFE53935);

  final _supabase = Supabase.instance.client;

  bool _carregando = false;

  bool _salvando = false;

  String? _editandoId;

  String _categoria = 'geral';

  String _prioridade = 'normal';

  String _tipoCampanha = 'campanha';

  String _regraEvento = 'nova_oportunidade';

  final _imagemUrl = TextEditingController();

  final _textoBotao = TextEditingController();

  final _limite = TextEditingController(text: '3');

  List<Map<String, dynamic>> _campanhas = [];

  List<Map<String, dynamic>> _historico = [];

  int _total = 0;

  int _naoLidas = 0;

  int _lidas = 0;

  int _cliques = 0;

  int _aba = 0;

  final _titulo = TextEditingController();

  final _mensagem = TextEditingController();

  final _destino = TextEditingController();

  // Localidades obtidas diretamente de tab_localidades.
  final Set<String> _estadosSelecionados = {};
  final Set<String> _cidadesSelecionadas = {};
  List<Map<String, String>> _localidades = [];
  bool _carregandoLocalidades = false;
  String? _erroLocalidades;

  // Destinatários específicos da tab_usuarios.
  final Set<String> _usuariosSelecionados = {};
  final Map<String, String> _nomesSelecionados = {};
  final _buscaUsuario = TextEditingController();

  // Identificadores compatíveis com o roteamento do sininho.
  static const Map<String, String> _destinos = {
    '': 'Nenhuma tela (somente leitura)',
    'feed': 'Feed',
    'perfil': 'Meu perfil',
    'servicos': 'Serviços',
    'planos': 'Planos',
    'mensagens': 'Mensagens',
    'jisa': 'Jisa IA',
    'orcamentos': 'Orçamentos',
    'compras': 'Lista de compras',
    'selo_verificacao': 'Selo de verificação',
    'faq': 'Perguntas frequentes',
    'suporte': 'Suporte',
  };

  final _horarios = <TimeOfDay>[const TimeOfDay(hour: 8, minute: 0)];

  final _dias = <int>{1, 2, 3, 4, 5};

  String _publico = 'Todos os usuários';

  String _repeticao = 'Uma vez';

  bool _somenteNaoLidas = true;

  bool _ativa = true;

  DateTime? _data;

  @override
  void initState() {
    super.initState();

    _recarregar();
    _carregarLocalidades();
  }

  @override
  void dispose() {
    _titulo.dispose();

    _mensagem.dispose();

    _destino.dispose();
    _buscaUsuario.dispose();

    _imagemUrl.dispose();

    _textoBotao.dispose();

    _limite.dispose();

    super.dispose();
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _painel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );

  Widget _campo(String titulo, TextEditingController controller,
          {int linhas = 1, String? dica}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: linhas,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: dica,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: _fundo,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _laranja)),
            ),
          ),
        ],
      );

  String _hora(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _adicionarHorario() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              const ColorScheme.dark(primary: _laranja, surface: _painel),
        ),
        child: child!,
      ),
    );

    if (hora == null || !mounted) return;

    if (_horarios.any((h) => h.hour == hora.hour && h.minute == hora.minute))
      return;

    setState(() {
      _horarios.add(hora);

      _horarios.sort((a, b) => a.hour * 60 + a.minute - b.hour * 60 - b.minute);
    });
  }

  void _mensagemStatus(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensagem),
      backgroundColor: erro ? _vermelho : const Color(0xFF23875C),
    ));
  }

  Future<void> _recarregar() async {
    if (!mounted) return;

    setState(() => _carregando = true);

    try {
      final rows = await _supabase
          .from('tab_notificacoes_internas')
          .select('*')
          .order('criada_em', ascending: false)
          .limit(1000);

      final dados = List<Map<String, dynamic>>.from(rows);

      final notificacoes =
          dados.where((r) => r['tipo_registro'] == 'notificacao').toList();

      if (!mounted) return;

      setState(() {
        _campanhas = dados
            .where((r) =>
                r['tipo_registro'] == 'campanha' ||
                r['tipo_registro'] == 'automacao')
            .toList();

        _historico = notificacoes;

        _total = notificacoes.length;

        _naoLidas = notificacoes.where((r) => r['lida'] != true).length;

        _lidas = notificacoes.where((r) => r['lida'] == true).length;

        _cliques = notificacoes.where((r) => r['clicada_em'] != null).length;
      });
    } catch (e) {
      _mensagemStatus('Erro ao carregar dados: $e', erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _texto(Map<String, dynamic> r, List<String> campos) {
    for (final campo in campos) {
      final valor = r[campo]?.toString().trim() ?? '';
      if (valor.isNotEmpty && valor.toLowerCase() != 'null') return valor;
    }
    return '';
  }

  // A estrutura de tab_localidades pode variar entre instalações.
  // Aceitamos os nomes de colunas usuais sem alterar o banco.
  Future<void> _carregarLocalidades() async {
    if (_carregandoLocalidades) return;
    setState(() {
      _carregandoLocalidades = true;
      _erroLocalidades = null;
    });
    try {
      final todas = <Map<String, dynamic>>[];
      for (var inicio = 0; inicio < 20000; inicio += 1000) {
        final lote = await _supabase
            .from('tab_localidades')
            .select('*')
            .range(inicio, inicio + 999);
        todas.addAll(List<Map<String, dynamic>>.from(lote));
        if (lote.length < 1000) break;
      }
      final unicas = <String, Map<String, String>>{};
      for (final r in todas) {
        final estado = _texto(r, [
          'uf',
          'estado_sigla',
          'sigla_uf',
          'sigla_estado',
          'estado',
          'uf_sigla'
        ]).toUpperCase();
        final cidade = _texto(r,
            ['cidade', 'nome_cidade', 'municipio', 'nome_municipio', 'nome']);
        if (estado.isEmpty) continue;
        if (cidade.isEmpty) {
          unicas.putIfAbsent(
              '$estado|', () => {'estado': estado, 'cidade': ''});
        } else {
          unicas['$estado|${cidade.toLowerCase()}'] = {
            'estado': estado,
            'cidade': cidade
          };
        }
      }
      if (!mounted) return;
      setState(() {
        _localidades = unicas.values.toList()
          ..sort((a, b) {
            final uf = a['estado']!.compareTo(b['estado']!);
            return uf != 0 ? uf : a['cidade']!.compareTo(b['cidade']!);
          });
        if (_localidades.isEmpty)
          _erroLocalidades =
              'Nenhum estado identificado. Confira as colunas e permissões de tab_localidades.';
      });
    } catch (e) {
      if (mounted)
        setState(
            () => _erroLocalidades = 'Falha ao consultar tab_localidades: $e');
    } finally {
      if (mounted) setState(() => _carregandoLocalidades = false);
    }
  }

  Future<void> _selecionarLocalidades({required bool estados}) async {
    if (_localidades.isEmpty) {
      _mensagemStatus(_erroLocalidades ?? 'Carregue as localidades antes.',
          erro: true);
      return;
    }
    final opcoes = estados
        ? (_localidades.map((e) => e['estado']!).toSet().toList()..sort())
        : (_localidades
            .where((e) =>
                _estadosSelecionados.isEmpty ||
                _estadosSelecionados.contains(e['estado']))
            .where((e) => e['cidade']!.isNotEmpty)
            .map((e) => '${e['estado']}|${e['cidade']}')
            .toSet()
            .toList()
          ..sort());
    final selecionadas =
        Set<String>.from(estados ? _estadosSelecionados : _cidadesSelecionadas);
    var busca = '';
    final resultado = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, atualizar) => AlertDialog(
                backgroundColor: _painel,
                title: Text(
                    estados ? 'Selecionar estados' : 'Selecionar cidades',
                    style: const TextStyle(color: Colors.white)),
                content: SizedBox(
                    width: 480,
                    height: 430,
                    child: Column(children: [
                      TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                              prefixIcon:
                                  Icon(Icons.search, color: Colors.white70),
                              hintText: 'Pesquisar',
                              hintStyle: TextStyle(color: Colors.white54)),
                          onChanged: (v) =>
                              atualizar(() => busca = v.toLowerCase())),
                      Expanded(
                          child: ListView(
                              children: opcoes
                                  .where((e) => e.toLowerCase().contains(busca))
                                  .map((v) => CheckboxListTile(
                                        dense: true,
                                        activeColor: _laranja,
                                        checkColor: Colors.black,
                                        title: Text(
                                            estados
                                                ? v
                                                : v.replaceFirst('|', ' - '),
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        value: selecionadas.contains(v),
                                        onChanged: (marcado) => atualizar(() {
                                          if (marcado == true) {
                                            selecionadas.add(v);
                                          } else {
                                            selecionadas.remove(v);
                                          }
                                        }),
                                      ))
                                  .toList())),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, selecionadas),
                      child: const Text('Confirmar'))
                ],
              )),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      if (estados) {
        _estadosSelecionados
          ..clear()
          ..addAll(resultado);
        _cidadesSelecionadas.removeWhere((v) =>
            _estadosSelecionados.isNotEmpty &&
            !_estadosSelecionados.contains(v.split('|').first));
      } else {
        _cidadesSelecionadas
          ..clear()
          ..addAll(resultado);
      }
    });
  }

  Future<void> _selecionarUsuarios() async {
    final escolhidos = Set<String>.from(_usuariosSelecionados);
    final nomes = Map<String, String>.from(_nomesSelecionados);
    var buscando = false;
    var termo = '';
    var pagina = 0;
    var resultados = <Map<String, dynamic>>[];
    String? erro;
    // Pesquisa paginada no servidor, sem carregar a base inteira de usuários.
    Future<void> carregar(StateSetter atualizar, {bool proxima = false}) async {
      atualizar(() {
        buscando = true;
        erro = null;
      });
      try {
        final inicio = (proxima ? pagina + 1 : 0) * 50;
        var query = _supabase
            .from('tab_usuarios')
            .select('id,usuario_nome,email,cidade,estado,usuario_tipo');
        if (termo.trim().isNotEmpty) {
          final t = termo
              .trim()
              .replaceAll(',', ' ')
              .replaceAll('%', '')
              .replaceAll('*', '');
          query = query.or('usuario_nome.ilike.%$t%,email.ilike.%$t%');
        }
        final dados =
            await query.order('usuario_nome').range(inicio, inicio + 49);
        atualizar(() {
          resultados = List<Map<String, dynamic>>.from(dados);
          pagina = proxima ? pagina + 1 : 0;
        });
      } catch (e) {
        atualizar(() => erro = e.toString());
      } finally {
        atualizar(() => buscando = false);
      }
    }

    if (!mounted) return;
    final resultado = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, atualizar) {
                // A busca inicial é acionada por botão para não fazer chamadas no build.
                return AlertDialog(
                  backgroundColor: _painel,
                  title: const Text('Selecionar usuários',
                      style: TextStyle(color: Colors.white)),
                  content: SizedBox(
                      width: 580,
                      height: 480,
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: _buscaUsuario,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                      hintText: 'Nome ou e-mail',
                                      hintStyle:
                                          TextStyle(color: Colors.white54)),
                                  onSubmitted: (v) {
                                    termo = v;
                                    carregar(atualizar);
                                  })),
                          IconButton(
                              tooltip: 'Pesquisar',
                              icon: const Icon(Icons.search, color: _laranja),
                              onPressed: () {
                                termo = _buscaUsuario.text;
                                carregar(atualizar);
                              })
                        ]),
                        Text('${escolhidos.length} selecionado(s)',
                            style: const TextStyle(color: Colors.white70)),
                        if (erro != null)
                          Text(erro!,
                              style: const TextStyle(color: Colors.redAccent)),
                        if (buscando) const LinearProgressIndicator(),
                        Expanded(
                            child: ListView(
                                children: resultados.map((u) {
                          final id = u['id'].toString();
                          final nome = (u['usuario_nome'] ?? '').toString();
                          return CheckboxListTile(
                            activeColor: _laranja,
                            checkColor: Colors.black,
                            value: escolhidos.contains(id),
                            title: Text(nome,
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text(
                                '${u['email'] ?? ''} • ${u['cidade'] ?? ''}/${u['estado'] ?? ''}',
                                style: const TextStyle(color: Colors.white54)),
                            onChanged: (v) => atualizar(() {
                              if (v == true) {
                                escolhidos.add(id);
                                nomes[id] = nome;
                              } else {
                                escolhidos.remove(id);
                                nomes.remove(id);
                              }
                            }),
                          );
                        }).toList())),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                  onPressed: buscando || pagina == 0
                                      ? null
                                      : () => carregar(atualizar),
                                  child: const Text('Primeira página')),
                              TextButton(
                                  onPressed: buscando || resultados.length < 50
                                      ? null
                                      : () =>
                                          carregar(atualizar, proxima: true),
                                  child: const Text('Próxima página')),
                            ]),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirmar'))
                  ],
                );
              },
            ));
    if (resultado == true && mounted)
      setState(() {
        _usuariosSelecionados
          ..clear()
          ..addAll(escolhidos);
        _nomesSelecionados
          ..clear()
          ..addAll(nomes);
      });
  }

  Widget _segmentacaoWidget() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('País: Brasil',
            style:
                TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _carregandoLocalidades
                  ? null
                  : () => _selecionarLocalidades(estados: true),
              icon: const Icon(Icons.map_outlined),
              label: Text('Estados (${_estadosSelecionados.length})')),
          OutlinedButton.icon(
              onPressed: _carregandoLocalidades
                  ? null
                  : () => _selecionarLocalidades(estados: false),
              icon: const Icon(Icons.location_city),
              label: Text('Cidades (${_cidadesSelecionadas.length})')),
          TextButton(
              onPressed: () => setState(() {
                    _estadosSelecionados.clear();
                    _cidadesSelecionadas.clear();
                  }),
              child: const Text('Brasil inteiro')),
          if (_carregandoLocalidades) const CircularProgressIndicator(),
        ]),
        if (_erroLocalidades != null)
          Text(_erroLocalidades!,
              style: const TextStyle(color: Colors.orangeAccent)),
        if (_estadosSelecionados.isNotEmpty)
          Text('Estados: ${_estadosSelecionados.join(', ')}',
              style: const TextStyle(color: Colors.white70)),
        if (_cidadesSelecionadas.isNotEmpty)
          Text(
              'Cidades: ${_cidadesSelecionadas.map((e) => e.replaceFirst('|', '/')).join(', ')}',
              style: const TextStyle(color: Colors.white70)),
        if (_publico == 'Usuários selecionados') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _selecionarUsuarios,
              icon: const Icon(Icons.people_alt_outlined),
              label:
                  Text('Escolher usuários (${_usuariosSelecionados.length})')),
          if (_usuariosSelecionados.isNotEmpty)
            Text(
                _usuariosSelecionados
                    .map((id) => _nomesSelecionados[id] ?? id)
                    .join(', '),
                style: const TextStyle(color: Colors.white70)),
        ],
        const SizedBox(height: 10),
        const Text(
            'O público selecionado será respeitado pelo executor de notificações internas.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]);

  String _codigoPublico(String valor) {
    switch (valor) {
      case 'Clientes':
        return 'cliente';

      case 'Profissionais':
        return 'profissional';

      case 'Arquitetos':
        return 'arquiteto';

      case 'Engenheiros':
        return 'engenheiro';

      case 'Usuários selecionados':
        return 'selecionados';

      default:
        return 'todos';
    }
  }

  String _rotuloPublico(String? valor) {
    switch (valor) {
      case 'cliente':
        return 'Clientes';

      case 'profissional':
        return 'Profissionais';

      case 'arquiteto':
        return 'Arquitetos';

      case 'engenheiro':
        return 'Engenheiros';

      case 'selecionados':
        return 'Usuários selecionados';

      default:
        return 'Todos os usuários';
    }
  }

  String _codigoRecorrencia(String valor) {
    switch (valor) {
      case 'Diariamente':
        return 'diaria';

      case 'Semanalmente':
        return 'semanal';

      case 'Mensalmente':
        return 'mensal';

      default:
        return 'uma_vez';
    }
  }

  String _rotuloRecorrencia(String? valor) {
    switch (valor) {
      case 'diaria':
        return 'Diariamente';

      case 'semanal':
        return 'Semanalmente';

      case 'mensal':
        return 'Mensalmente';

      default:
        return 'Uma vez';
    }
  }

  DateTime? _primeiraExecucao() {
    if (_horarios.isEmpty) return null;

    final base = _data ?? DateTime.now();

    final ordenados = [..._horarios]
      ..sort((a, b) => a.hour * 60 + a.minute - b.hour * 60 - b.minute);

    for (int i = 0;
        i < (_repeticao == 'Uma vez' && _data != null ? 1 : 370);
        i++) {
      final dia =
          DateTime(base.year, base.month, base.day).add(Duration(days: i));

      if (_dias.isNotEmpty && !_dias.contains(dia.weekday)) continue;

      for (final h in ordenados) {
        final momento =
            DateTime(dia.year, dia.month, dia.day, h.hour, h.minute);

        if (momento.isAfter(DateTime.now())) return momento;
      }
    }

    return null;
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    if (_titulo.text.trim().isEmpty || _mensagem.text.trim().isEmpty) {
      _mensagemStatus('Informe o título e a mensagem.', erro: true);

      return;
    }

    if (_horarios.isEmpty || _dias.isEmpty) {
      _mensagemStatus('Selecione pelo menos um horário e um dia da semana.',
          erro: true);

      return;
    }

    if (_publico == 'Usuários selecionados' && _usuariosSelecionados.isEmpty) {
      _mensagemStatus('Selecione pelo menos um usuário.', erro: true);
      return;
    }

    final proxima = _primeiraExecucao();

    if (proxima == null) {
      _mensagemStatus('Não há uma próxima data válida para esse agendamento.',
          erro: true);

      return;
    }

    final usuario = _supabase.auth.currentUser;

    if (usuario == null) {
      _mensagemStatus('Sessão expirada. Entre novamente.', erro: true);

      return;
    }

    setState(() => _salvando = true);

    try {
      final agendamento = <String, dynamic>{
        'fuso': 'America/Sao_Paulo',
        'horarios': _horarios.map(_hora).toList()..sort(),
        'dias_semana': _dias.toList()..sort(),
        'recorrencia': _codigoRecorrencia(_repeticao),
      };

      // O estado do botão determina a ativação, inclusive para segmentações.
      // A Edge Function já trata usuarios_ids, estados e cidades.
      final ativar = _ativa;
      final dados = <String, dynamic>{
        'tipo_registro': _tipoCampanha,

        'titulo': _titulo.text.trim(),

        'mensagem': _mensagem.text.trim(),

        'categoria': _categoria,

        'prioridade': _prioridade,

        'destino': _destino.text.trim().isEmpty ? null : _destino.text.trim(),

        'imagem_url':
            _imagemUrl.text.trim().isEmpty ? null : _imagemUrl.text.trim(),

        'texto_botao':
            _textoBotao.text.trim().isEmpty ? null : _textoBotao.text.trim(),

        'publico': {
          'tipo': _codigoPublico(_publico),
          'pais': 'Brasil',
          'cidade': _cidadesSelecionadas.length == 1
              ? _cidadesSelecionadas.first.split('|').last
              : '',
          'estado': _estadosSelecionados.length == 1
              ? _estadosSelecionados.first
              : '',
          'estados': _estadosSelecionados.toList()..sort(),
          'cidades': _cidadesSelecionadas.map((e) => e.split('|').last).toList()
            ..sort(),
          'cidades_uf': _cidadesSelecionadas.map((e) {
            final partes = e.split('|');
            return {'estado': partes.first, 'cidade': partes.last};
          }).toList(),
          'usuarios_ids': _publico == 'Usuários selecionados'
              ? (_usuariosSelecionados.toList()..sort())
              : <String>[],
        },

        'agendamento': agendamento,

        'regra_evento': _tipoCampanha == 'automacao' ? _regraEvento : null,

        'somente_se_nao_lida': _somenteNaoLidas,

        'limite_por_usuario': int.tryParse(_limite.text.trim()) ?? 3,

        'ativo': ativar,

        // Segurança: salvar uma configuração não publica notificações.

        // O executor backend será responsável pela distribuição.

        'status': ativar ? 'agendada' : 'pausada',

        'inicio_em': _data?.toIso8601String(),

        'proxima_execucao_em':
            ativar ? proxima.toUtc().toIso8601String() : null,

        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      };

      if (_editandoId == null) {
        dados['criado_por'] = usuario.id;

        await _supabase.from('tab_notificacoes_internas').insert(dados);
      } else {
        await _supabase
            .from('tab_notificacoes_internas')
            .update(dados)
            .eq('id', _editandoId!);
      }

      if (!mounted) return;

      _mensagemStatus(ativar
          ? 'Campanha salva ativa. A distribuição depende do executor backend.'
          : 'Campanha salva pausada.');

      _limparEditor();

      await _recarregar();
    } catch (e) {
      _mensagemStatus('Falha ao salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _limparEditor() {
    _titulo.clear();

    _mensagem.clear();

    _destino.clear();
    _estadosSelecionados.clear();
    _cidadesSelecionadas.clear();
    _usuariosSelecionados.clear();
    _nomesSelecionados.clear();

    _imagemUrl.clear();

    _textoBotao.clear();

    _limite.text = '3';

    setState(() {
      _editandoId = null;

      _tipoCampanha = 'campanha';

      _categoria = 'geral';

      _prioridade = 'normal';

      _regraEvento = 'nova_oportunidade';

      _publico = 'Todos os usuários';

      _repeticao = 'Uma vez';

      _somenteNaoLidas = true;

      _ativa = true;

      _data = null;

      _horarios
        ..clear()
        ..add(const TimeOfDay(hour: 8, minute: 0));

      _dias
        ..clear()
        ..addAll([1, 2, 3, 4, 5]);
    });
  }

  void _editar(Map<String, dynamic> registro) {
    final publico = Map<String, dynamic>.from(
        registro['publico'] is Map ? registro['publico'] as Map : {});

    final agenda = Map<String, dynamic>.from(
        registro['agendamento'] is Map ? registro['agendamento'] as Map : {});

    _titulo.text = (registro['titulo'] ?? '').toString();

    _mensagem.text = (registro['mensagem'] ?? '').toString();

    _estadosSelecionados.clear();
    _cidadesSelecionadas.clear();
    _usuariosSelecionados.clear();
    _nomesSelecionados.clear();
    final estados = publico['estados'];
    if (estados is List)
      _estadosSelecionados.addAll(estados.map((e) => e.toString()));
    else if ((publico['estado'] ?? '').toString().isNotEmpty)
      _estadosSelecionados.add(publico['estado'].toString());
    final cidadesUf = publico['cidades_uf'];
    if (cidadesUf is List) {
      for (final c in cidadesUf) {
        if (c is Map && c['estado'] != null && c['cidade'] != null) {
          _cidadesSelecionadas.add('${c['estado']}|${c['cidade']}');
        }
      }
    } else if ((publico['cidade'] ?? '').toString().isNotEmpty &&
        _estadosSelecionados.length == 1) {
      _cidadesSelecionadas
          .add('${_estadosSelecionados.first}|${publico['cidade']}');
    }
    if (publico['usuarios_ids'] is List)
      _usuariosSelecionados
          .addAll((publico['usuarios_ids'] as List).map((e) => e.toString()));

    _destino.text = (registro['destino'] ?? '').toString();

    _imagemUrl.text = (registro['imagem_url'] ?? '').toString();

    _textoBotao.text = (registro['texto_botao'] ?? '').toString();

    _limite.text = (registro['limite_por_usuario'] ?? 3).toString();

    final listaHorarios =
        (agenda['horarios'] is List ? agenda['horarios'] as List : []);

    final listaDias =
        (agenda['dias_semana'] is List ? agenda['dias_semana'] as List : []);

    setState(() {
      _editandoId = registro['id'].toString();

      _tipoCampanha =
          registro['tipo_registro'] == 'automacao' ? 'automacao' : 'campanha';

      _categoria = (registro['categoria'] ?? 'geral').toString();

      _prioridade = (registro['prioridade'] ?? 'normal').toString();

      _regraEvento =
          (registro['regra_evento'] ?? 'nova_oportunidade').toString();

      _publico = _rotuloPublico(publico['tipo']?.toString());

      _repeticao = _rotuloRecorrencia(agenda['recorrencia']?.toString());

      _somenteNaoLidas = registro['somente_se_nao_lida'] == true;

      _ativa = registro['ativo'] == true;

      _data = DateTime.tryParse((registro['inicio_em'] ?? '').toString())
          ?.toLocal();

      _horarios.clear();

      for (final h in listaHorarios) {
        final partes = h.toString().split(':');

        if (partes.length == 2) {
          final hh = int.tryParse(partes[0]);

          final mm = int.tryParse(partes[1]);

          if (hh != null &&
              mm != null &&
              hh >= 0 &&
              hh < 24 &&
              mm >= 0 &&
              mm < 60) {
            _horarios.add(TimeOfDay(hour: hh, minute: mm));
          }
        }
      }

      if (_horarios.isEmpty) _horarios.add(const TimeOfDay(hour: 8, minute: 0));

      _dias
        ..clear()
        ..addAll(listaDias
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((e) => e >= 1 && e <= 7));

      if (_dias.isEmpty) _dias.addAll([1, 2, 3, 4, 5]);

      _aba = 1;
    });
  }

  // Calcula a próxima execução ao reativar uma campanha já salva.
  // Mantém os mesmos critérios de horários e dias usados no formulário.
  DateTime? _proximaExecucaoSalva(Map<String, dynamic> registro) {
    final ag = registro['agendamento'] is Map
        ? Map<String, dynamic>.from(registro['agendamento'] as Map)
        : <String, dynamic>{};
    final horarios = <TimeOfDay>[];
    for (final item in (ag['horarios'] is List ? ag['horarios'] as List : [])) {
      final partes = item.toString().split(':');
      if (partes.length != 2) continue;
      final h = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        horarios.add(TimeOfDay(hour: h, minute: m));
      }
    }
    if (horarios.isEmpty) return null;
    horarios.sort((a, b) => a.hour * 60 + a.minute - b.hour * 60 - b.minute);
    final dias = (ag['dias_semana'] is List ? ag['dias_semana'] as List : [])
        .map((e) => int.tryParse(e.toString()))
        .whereType<int>()
        .toSet();
    final recorrencia = (ag['recorrencia'] ?? 'uma_vez').toString();
    final inicio =
        DateTime.tryParse((registro['inicio_em'] ?? '').toString())?.toLocal();
    final agora = DateTime.now();
    final base = inicio ?? agora;
    final tentativas = recorrencia == 'uma_vez' && inicio != null ? 1 : 370;
    for (var i = 0; i < tentativas; i++) {
      final dia = DateTime(base.year, base.month, base.day + i);
      if (dias.isNotEmpty && !dias.contains(dia.weekday)) continue;
      if (recorrencia == 'mensal' && dia.day != base.day) continue;
      for (final h in horarios) {
        final momento =
            DateTime(dia.year, dia.month, dia.day, h.hour, h.minute);
        if (momento.isAfter(agora)) return momento;
      }
    }
    return null;
  }

  Future<void> _alterarAtivo(Map<String, dynamic> registro) async {
    final novo = registro['ativo'] != true;
    final proxima = novo ? _proximaExecucaoSalva(registro) : null;
    if (novo && proxima == null) {
      _mensagemStatus(
          'Não há próxima execução válida. Edite o agendamento antes de reativar.',
          erro: true);
      return;
    }

    try {
      await _supabase.from('tab_notificacoes_internas').update({
        'ativo': novo,
        'status': novo ? 'agendada' : 'pausada',
        'proxima_execucao_em': novo ? proxima!.toUtc().toIso8601String() : null,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', registro['id']);

      _mensagemStatus(
          novo ? 'Configuração reativada.' : 'Configuração pausada.');

      await _recarregar();
    } catch (e) {
      _mensagemStatus('Não foi possível alterar: $e', erro: true);
    }
  }

  Future<void> _excluir(Map<String, dynamic> registro) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir configuração?'),
        content: Text(
            'Excluir "${registro['titulo']}"? As notificações já registradas para usuários não serão apagadas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _supabase
          .from('tab_notificacoes_internas')
          .delete()
          .eq('id', registro['id']);

      _mensagemStatus('Configuração excluída.');

      await _recarregar();
    } catch (e) {
      _mensagemStatus('Falha ao excluir: $e', erro: true);
    }
  }

  String _formatarData(dynamic valor) {
    final data = DateTime.tryParse((valor ?? '').toString())?.toLocal();

    if (data == null) return '—';

    String d(int n) => n.toString().padLeft(2, '0');

    return '${d(data.day)}/${d(data.month)}/${data.year} ${d(data.hour)}:${d(data.minute)}';
  }

  Widget _listaCampanhas({bool somenteAutomacoes = false}) {
    final lista = _campanhas
        .where(
            (r) => somenteAutomacoes ? r['tipo_registro'] == 'automacao' : true)
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: Text('Configurações cadastradas',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold))),
        IconButton(
            onPressed: _recarregar,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh, color: _laranja)),
      ]),
      if (lista.isEmpty)
        _card(
            child: const Text('Nenhuma configuração cadastrada.',
                style: TextStyle(color: Colors.white70))),
      ...lista.map((r) {
        final ag = r['agendamento'] is Map ? r['agendamento'] as Map : {};

        final horas =
            ag['horarios'] is List ? (ag['horarios'] as List).join(', ') : '—';

        return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _card(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text((r['titulo'] ?? '').toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Chip(
                          label: Text(r['ativo'] == true ? 'Ativa' : 'Pausada'),
                          backgroundColor: r['ativo'] == true
                              ? const Color(0xFF20513E)
                              : const Color(0xFF5C3026)),
                      Chip(
                          label: Text(r['tipo_registro'] == 'automacao'
                              ? 'Automação'
                              : 'Campanha')),
                    ]),
                const SizedBox(height: 8),
                Text((r['mensagem'] ?? '').toString(),
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                    'Horários: $horas  •  Próxima execução prevista: ${_formatarData(r['proxima_execucao_em'])}',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                      onPressed: () => _editar(r),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar')),
                  TextButton.icon(
                      onPressed: () => _alterarAtivo(r),
                      icon: Icon(r['ativo'] == true
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline),
                      label: Text(r['ativo'] == true ? 'Pausar' : 'Reativar')),
                  TextButton.icon(
                      onPressed: () => _excluir(r),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Excluir')),
                ]),
              ],
            )));
      }),
    ]);
  }

  Widget _historicoWidget() => Column(children: [
        _card(
            child: const Text(
                'Histórico das notificações individuais registradas no Supabase (até 1.000 registros recentes).',
                style: TextStyle(color: Colors.white70))),
        const SizedBox(height: 12),
        if (_historico.isEmpty)
          _card(
              child: const Text('Nenhuma notificação individual registrada.',
                  style: TextStyle(color: Colors.white70))),
        ..._historico.take(100).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _card(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text((r['titulo'] ?? '').toString(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text((r['mensagem'] ?? '').toString(),
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 5),
                  Text(
                      '${r['lida'] == true ? 'Lida' : 'Não lida'} • ${_formatarData(r['criada_em'])} • Usuário: ${r['usuario_id'] ?? '—'}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ])))),
      ]);

  Widget _relatoriosWidget() => _card(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Indicadores reais (até 1.000 registros recentes)',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        const SizedBox(height: 12),
        Text('Notificações registradas: $_total',
            style: const TextStyle(color: Colors.white70)),
        Text('Lidas: $_lidas', style: const TextStyle(color: Colors.white70)),
        Text('Não lidas: $_naoLidas',
            style: const TextStyle(color: Colors.white70)),
        Text('Cliques: $_cliques',
            style: const TextStyle(color: Colors.white70)),
        Text(
            'Taxa de leitura: ${_total == 0 ? '0.0' : (_lidas * 100 / _total).toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 10),
        const Text(
            'Os números representam registros existentes, não execuções futuras. Para métricas globais sem limite será necessária uma consulta agregada no backend.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]));

  Widget _cabecalho() => _card(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 18,
          runSpacing: 14,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                  color: _laranja.withOpacity(.12),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.notifications_none_rounded,
                  color: _laranja, size: 30),
            ),
            const SizedBox(
              width: 470,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Central de Notificações Internas',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 5),
                    Text(
                        'Campanhas e automações exclusivas do sininho. Sem notificações push.',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
            ),
            const Chip(
              backgroundColor: Color(0xFF352B20),
              label: Text('Configuração inicial',
                  style: TextStyle(color: _laranja)),
            ),
          ],
        ),
      );

  Widget _indicador(IconData icone, String titulo, String valor, Color cor) =>
      Expanded(
          child: _card(
              child: Row(children: [
        Icon(icone, color: cor, size: 26),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold)),
          Text(titulo,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ])),
      ])));

  Widget _dashboard() => Column(children: [
        LayoutBuilder(builder: (context, c) {
          final itens = [
            (
              Icons.mark_email_read_outlined,
              'Notificações registradas',
              '—',
              _laranja
            ),
            (
              Icons.mark_email_unread_outlined,
              'Não lidas',
              '$_naoLidas',
              _vermelho
            ),
            (Icons.done_all, 'Lidas', '$_lidas', Colors.greenAccent),
            (
              Icons.ads_click_outlined,
              'Cliques',
              '$_cliques',
              Colors.lightBlueAccent
            ),
          ];

          return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: itens
                  .map((i) => SizedBox(
                        width: c.maxWidth > 800
                            ? (c.maxWidth - 36) / 4
                            : c.maxWidth > 450
                                ? (c.maxWidth - 12) / 2
                                : c.maxWidth,
                        child: _card(
                            child: Row(children: [
                          Icon(i.$1, color: i.$4),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(i.$3,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                Text(i.$2,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 12)),
                              ])),
                        ])),
                      ))
                  .toList());
        }),
        const SizedBox(height: 14),
        _card(
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Visão geral',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text(
                  'Indicadores calculados a partir de até 1.000 registros recentes. Os disparos programados exigem um executor backend, ainda não ativado.',
                  style: TextStyle(color: Colors.white70)),
            ])),
      ]);

  Widget _editor() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Conteúdo da notificação',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _tipoCampanha,
            dropdownColor: _painel,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Tipo de configuração',
                labelStyle: TextStyle(color: Colors.white70)),
            items: const [
              DropdownMenuItem(
                  value: 'campanha', child: Text('Campanha manual')),
              DropdownMenuItem(
                  value: 'automacao', child: Text('Automação por evento'))
            ],
            onChanged: (v) => setState(() => _tipoCampanha = v ?? 'campanha'),
          ),
          if (_tipoCampanha == 'automacao') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _regraEvento,
              dropdownColor: _painel,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Evento disparador',
                  labelStyle: TextStyle(color: Colors.white70)),
              items: const [
                DropdownMenuItem(
                    value: 'nova_oportunidade',
                    child: Text('Nova oportunidade')),
                DropdownMenuItem(
                    value: 'avaliacao_recebida', child: Text('Nova avaliação')),
                DropdownMenuItem(
                    value: 'selo_aprovado', child: Text('Selo aprovado')),
                DropdownMenuItem(
                    value: 'selo_vencido', child: Text('Selo vencido')),
                DropdownMenuItem(
                    value: 'plano_vencendo',
                    child: Text('Plano próximo do vencimento')),
                DropdownMenuItem(
                    value: 'usuario_inativo', child: Text('Usuário inativo')),
              ],
              onChanged: (v) =>
                  setState(() => _regraEvento = v ?? _regraEvento),
            ),
          ],
          const SizedBox(height: 12),
          _campo('Título', _titulo,
              dica: 'Ex.: Novas oportunidades na sua região'),
          const SizedBox(height: 14),
          _campo('Mensagem', _mensagem,
              linhas: 3, dica: 'Digite a mensagem que aparecerá no sininho'),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _destinos.containsKey(_destino.text) ? _destino.text : null,
            dropdownColor: _painel,
            isExpanded: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Destino / tela ao tocar na notificação',
                labelStyle: TextStyle(color: Colors.white70)),
            items: _destinos.entries
                .map((e) => DropdownMenuItem<String>(
                    value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _destino.text = v ?? ''),
          ),
          if (_destino.text.isNotEmpty && !_destinos.containsKey(_destino.text))
            Text('Destino antigo não reconhecido: ${_destino.text}',
                style: const TextStyle(color: Colors.orangeAccent)),
          const SizedBox(height: 12),
          _campo('Imagem (URL opcional)', _imagemUrl),
          const SizedBox(height: 12),
          _campo('Texto do botão (opcional)', _textoBotao),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 12, children: [
            SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  value: _categoria,
                  dropdownColor: _painel,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'Categoria',
                      labelStyle: TextStyle(color: Colors.white70)),
                  items: [
                    'geral',
                    'oportunidade',
                    'selo',
                    'plano',
                    'avaliacao',
                    'seguranca',
                    'promocao'
                  ]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _categoria = v ?? _categoria),
                )),
            SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  value: _prioridade,
                  dropdownColor: _painel,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'Prioridade',
                      labelStyle: TextStyle(color: Colors.white70)),
                  items: ['normal', 'importante', 'urgente']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _prioridade = v ?? _prioridade),
                )),
          ]),
          const SizedBox(height: 10),
          const Text(
              'Variáveis planejadas: {nome}, {cidade}, {profissao}, {plano}',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        const SizedBox(height: 14),
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Público e segmentação',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _publico,
            dropdownColor: _painel,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Destinatários',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24))),
            items: [
              'Todos os usuários',
              'Clientes',
              'Profissionais',
              'Arquitetos',
              'Engenheiros',
              'Usuários selecionados'
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _publico = v ?? _publico),
          ),
          const SizedBox(height: 14),
          _segmentacaoWidget(),
        ])),
        const SizedBox(height: 14),
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Relógio e programação',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._horarios.map((h) => InputChip(
                      backgroundColor: _fundo,
                      label: Text(_hora(h),
                          style: const TextStyle(color: Colors.white)),
                      deleteIconColor: Colors.redAccent,
                      onDeleted: () => setState(() => _horarios.remove(h)),
                    )),
                OutlinedButton.icon(
                    onPressed: _adicionarHorario,
                    icon: const Icon(Icons.add_alarm),
                    label: const Text('Adicionar horário'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _laranja,
                        side: const BorderSide(color: _laranja))),
              ]),
          const SizedBox(height: 12),
          const Text('Dias da semana',
              style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                final dia = i + 1;

                final nomes = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

                return FilterChip(
                  selected: _dias.contains(dia),
                  label: Text(nomes[i]),
                  selectedColor: _laranja,
                  backgroundColor: _fundo,
                  labelStyle: TextStyle(
                      color: _dias.contains(dia) ? Colors.black : Colors.white),
                  onSelected: (v) =>
                      setState(() => v ? _dias.add(dia) : _dias.remove(dia)),
                );
              })),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _repeticao,
            dropdownColor: _painel,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Repetição',
                labelStyle: TextStyle(color: Colors.white70)),
            items: ['Uma vez', 'Diariamente', 'Semanalmente', 'Mensalmente']
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _repeticao = v ?? _repeticao),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _data ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100));

              if (d != null && mounted) setState(() => _data = d);
            },
            icon: const Icon(Icons.event),
            label: Text(_data == null
                ? 'Escolher data inicial (opcional)'
                : 'Início: ${_data!.day.toString().padLeft(2, '0')}/${_data!.month.toString().padLeft(2, '0')}/${_data!.year}'),
            style: OutlinedButton.styleFrom(
                foregroundColor: _laranja,
                side: const BorderSide(color: _laranja)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repetir somente para quem ainda não leu',
                style: TextStyle(color: Colors.white)),
            value: _somenteNaoLidas,
            activeColor: _laranja,
            onChanged: (v) => setState(() => _somenteNaoLidas = v),
          ),
          _campo('Limite de notificações por usuário', _limite, dica: 'Ex.: 3'),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Campanha ativa',
                style: TextStyle(color: Colors.white)),
            value: _ativa,
            activeColor: _laranja,
            onChanged: (v) => setState(() => _ativa = v),
          ),
        ])),
        const SizedBox(height: 14),
        Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.save_outlined),
              label: Text(_salvando
                  ? 'Salvando...'
                  : _editandoId == null
                      ? 'Salvar no Supabase'
                      : 'Atualizar configuração'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _laranja,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
            )),
      ]);

  Widget _pendente(String titulo, String descricao, IconData icone) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icone, color: _laranja, size: 30),
          const SizedBox(height: 12),
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(descricao,
              style: const TextStyle(color: Colors.white70, height: 1.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    const titulos = [
      'Dashboard',
      'Campanhas',
      'Automações',
      'Histórico',
      'Relatórios'
    ];

    const icones = [
      Icons.dashboard_outlined,
      Icons.campaign_outlined,
      Icons.auto_awesome_outlined,
      Icons.history,
      Icons.bar_chart
    ];

    return Container(
      color: _fundo,
      child: Column(children: [
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _cabecalho(),
              const SizedBox(height: 14),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      children: List.generate(
                          titulos.length,
                          (i) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  selected: _aba == i,
                                  onSelected: (_) => setState(() => _aba = i),
                                  avatar: Icon(icones[i],
                                      size: 18,
                                      color:
                                          _aba == i ? Colors.black : _laranja),
                                  label: Text(titulos[i]),
                                  selectedColor: _laranja,
                                  backgroundColor: _painel,
                                  labelStyle: TextStyle(
                                      color: _aba == i
                                          ? Colors.black
                                          : Colors.white),
                                ),
                              )))),
              const SizedBox(height: 16),
              if (_aba == 0) _dashboard(),
              if (_aba == 1) ...[
                _editor(),
                const SizedBox(height: 22),
                _listaCampanhas()
              ],
              if (_aba == 2) _listaCampanhas(somenteAutomacoes: true),
              if (_aba == 3) _historicoWidget(),
              if (_aba == 4) _relatoriosWidget(),
            ]),
          )),
        )),
      ]),
    );
  }
}
