import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'metricas_crescimento_page.dart';

import 'metricas_usuarios_page.dart';

import 'metricas_localizacao_page.dart';

import 'metricas_publico_page.dart';

import 'metricas_engajamento_page.dart';

import 'metricas_planos_page.dart';

import 'metricas_financeiro_page.dart';

import 'metricas_funil_page.dart';

import 'metricas_ia_page.dart';

import 'metricas_campanhas_page.dart';

import 'metricas_cancelamentos_page.dart';

import 'metricas_retencao_page.dart';

class MetricasPage extends StatefulWidget {
  const MetricasPage({super.key});

  @override
  State<MetricasPage> createState() => _MetricasPageState();
}

class _MetricasPageState extends State<MetricasPage> {
  static const Color _fundo = Color(0xFF1A2C42);

  static const Color _card = Color(0xFF101B2B);

  static const Color _laranja = Color(0xFFFF8C00);

  bool _carregando = true;

  String? _erro;

  int _totalUsuarios = 0;

  int _novos30Dias = 0;

  int _pagantes = 0;

  int _metaUsuarios = 10000;

  @override
  void initState() {
    super.initState();

    _carregarResumo();
  }

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

  bool _ehPago(dynamic nomePlano) {
    final plano = _normalizar(nomePlano);

    if (plano.isEmpty) return false;

    const naoPagos = {
      'gratis',
      'gratuito',
      'free',
      'teste',
      'cortesia',
      'parceria',
      'especial',
    };

    return !naoPagos.contains(plano);
  }

  DateTime? _data(dynamic valor) {
    if (valor == null) return null;

    return DateTime.tryParse(valor.toString().trim());
  }

  Future<void> _carregarResumo() async {
    if (!mounted) return;

    setState(() {
      _carregando = true;

      _erro = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('tab_usuarios')
          .select('id, nome_plano_ativo, dt_cadastro');

      final usuarios = List<Map<String, dynamic>>.from(
        (response as List).map((e) => Map<String, dynamic>.from(e)),
      );

      final agora = DateTime.now();

      final hoje = DateTime(agora.year, agora.month, agora.day);

      final inicio30 = hoje.subtract(const Duration(days: 29));

      int novos30 = 0;

      int pagantes = 0;

      for (final usuario in usuarios) {
        final cadastro = _data(usuario['dt_cadastro']);

        if (cadastro != null) {
          final d = DateTime(cadastro.year, cadastro.month, cadastro.day);

          if (!d.isBefore(inicio30) && !d.isAfter(hoje)) {
            novos30++;
          }
        }

        if (_ehPago(usuario['nome_plano_ativo'])) {
          pagantes++;
        }
      }

      if (!mounted) return;

      setState(() {
        _totalUsuarios = usuarios.length;

        _novos30Dias = novos30;

        _pagantes = pagantes;

        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar resumo de métricas: $e');

      if (!mounted) return;

      setState(() {
        _erro = e.toString();

        _carregando = false;
      });
    }
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

  String _percentualMeta() {
    if (_metaUsuarios <= 0) return '0,00%';

    final p = (_totalUsuarios / _metaUsuarios) * 100;

    return '${p.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  Future<void> _editarMeta() async {
    final controller = TextEditingController(text: _metaUsuarios.toString());

    final novaMeta = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _card,
          title: const Text(
            'Alterar meta de usuários',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Meta',
              labelStyle: TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _laranja),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () {
                final valor = int.tryParse(
                  controller.text.replaceAll('.', '').replaceAll(',', ''),
                );

                if (valor != null && valor > 0) {
                  Navigator.pop(dialogContext, valor);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _laranja),
              child: const Text(
                'APLICAR',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (novaMeta != null && mounted) {
      setState(() => _metaUsuarios = novaMeta);
    }
  }

  void _abrirUsuarios() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasUsuariosPage(),
      ),
    );
  }

  void _abrirCrescimento() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MetricasCrescimentoPage(metaInicial: _metaUsuarios),
      ),
    );
  }

  void _abrirLocalizacao() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasLocalizacaoPage(),
      ),
    );
  }

  void _abrirPublico() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasPublicoPage(),
      ),
    );
  }

  void _abrirEngajamento() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasEngajamentoPage(),
      ),
    );
  }

  void _abrirPlanos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasPlanosPage(),
      ),
    );
  }

  void _abrirFinanceiro() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasFinanceiroPage(),
      ),
    );
  }

  void _abrirFunil() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasFunilPage(),
      ),
    );
  }

  void _abrirIA() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasIAPage(),
      ),
    );
  }

  void _abrirCampanhas() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasCampanhasPage(),
      ),
    );
  }

  void _abrirCancelamentos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasCancelamentosPage(),
      ),
    );
  }

  void _abrirRetencao() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MetricasRetencaoPage(),
      ),
    );
  }

  void _moduloEmBreve(String titulo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$titulo será implementado na próxima etapa.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _fundo,
      child: RefreshIndicator(
        onRefresh: _carregarResumo,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cabecalho(),
              if (_erro != null) ...[
                const SizedBox(height: 18),
                _erroCard(),
              ],
              const SizedBox(height: 22),
              _resumo(),
              const SizedBox(height: 28),
              const Text(
                'Métricas',
                style: TextStyle(
                  color: _laranja,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Selecione uma área para abrir as informações detalhadas.',
                style: TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              _gradeModulos(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 720;

        final titulo = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: _laranja, size: 28),
                SizedBox(width: 10),
                Text(
                  'Métricas e Relatórios',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'Central de acompanhamento estratégico do Ache Obra.',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
          ],
        );

        final botao = OutlinedButton.icon(
          onPressed: _carregando ? null : _carregarResumo,
          icon: _carregando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _laranja,
                  ),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(_carregando ? 'Atualizando...' : 'Atualizar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _laranja,
            side: const BorderSide(color: _laranja),
          ),
        );

        if (compacto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titulo, const SizedBox(height: 14), botao],
          );
        }

        return Row(
          children: [
            Expanded(child: titulo),
            botao,
          ],
        );
      },
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
        'Não foi possível atualizar o resumo.\n$_erro',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _resumo() {
    final cards = [
      _ResumoCard(
        titulo: 'USUÁRIOS',
        valor: _numero(_totalUsuarios),
        detalhe: 'total cadastrado',
        icone: Icons.people_alt_outlined,
        onTap: _abrirUsuarios,
      ),
      _ResumoCard(
        titulo: 'CRESCIMENTO',
        valor: '+${_numero(_novos30Dias)}',
        detalhe: 'últimos 30 dias',
        icone: Icons.trending_up,
        onTap: _abrirCrescimento,
      ),
      _ResumoCard(
        titulo: 'PAGANTES',
        valor: _numero(_pagantes),
        detalhe: 'assinaturas pagas',
        icone: Icons.workspace_premium_outlined,
        onTap: _abrirPlanos,
      ),
      _ResumoCard(
        titulo: 'META',
        valor: _percentualMeta(),
        detalhe: '${_numero(_totalUsuarios)} / ${_numero(_metaUsuarios)}',
        icone: Icons.flag_outlined,
        onTap: _abrirCrescimento,
        onSecondaryAction: _editarMeta,
        secondaryIcon: Icons.edit_outlined,
      ),
    ];

    return _gradeResumo(cards);
  }

  Widget _gradeResumo(List<_ResumoCard> itens) {
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
          children: itens
              .map(
                (item) => SizedBox(
                  width: largura,
                  child: InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 130),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _laranja.withOpacity(.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(item.icone, color: _laranja),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.titulo,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (item.onSecondaryAction != null)
                                      InkWell(
                                        onTap: item.onSecondaryAction,
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            item.secondaryIcon,
                                            color: _laranja,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
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
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 23,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                const SizedBox(height: 5),
                                Text(
                                  item.detalhe,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white30,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _gradeModulos() {
    final modulos = [
      _Modulo(
        'Usuários',
        'Cadastros, tipos e status',
        Icons.people_alt_outlined,
        _abrirUsuarios,
      ),
      _Modulo(
        'Crescimento',
        'Períodos, evolução e meta',
        Icons.trending_up,
        _abrirCrescimento,
      ),
      _Modulo(
        'Localização',
        'Estados, cidades e regiões',
        Icons.location_on_outlined,
        _abrirLocalizacao,
      ),
      _Modulo(
        'Público',
        'Idade, sexo e perfil',
        Icons.groups_2_outlined,
        _abrirPublico,
      ),
      _Modulo(
        'Engajamento',
        'Acessos e utilização',
        Icons.touch_app_outlined,
        _abrirEngajamento,
      ),
      _Modulo(
        'Planos',
        'Gratuitos, pagos e recorrentes',
        Icons.workspace_premium_outlined,
        _abrirPlanos,
      ),
      _Modulo(
        'Financeiro',
        'Receitas e faturamento',
        Icons.account_balance_wallet_outlined,
        _abrirFinanceiro,
      ),
      _Modulo(
        'Funil',
        'Conversão dos usuários',
        Icons.filter_alt_outlined,
        _abrirFunil,
      ),
      _Modulo(
        'IA',
        'Uso dos recursos de IA',
        Icons.auto_awesome_outlined,
        _abrirIA,
      ),
      _Modulo(
        'Campanhas',
        'Promoções, indicações e premiações',
        Icons.campaign_outlined,
        _abrirCampanhas,
      ),
      _Modulo(
        'Cancelamentos',
        'Contas e planos cancelados',
        Icons.person_off_outlined,
        _abrirCancelamentos,
      ),
      _Modulo(
        'Retenção',
        'Permanência e recorrência',
        Icons.repeat,
        _abrirRetencao,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        int colunas = 3;

        if (constraints.maxWidth < 620) {
          colunas = 1;
        } else if (constraints.maxWidth < 950) {
          colunas = 2;
        }

        const gap = 12.0;

        final largura = (constraints.maxWidth - gap * (colunas - 1)) / colunas;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: modulos
              .map(
                (m) => SizedBox(
                  width: largura,
                  child: InkWell(
                    onTap: m.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _laranja.withOpacity(.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(m.icone, color: _laranja),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.titulo,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.subtitulo,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white30,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ResumoCard {
  final String titulo;

  final String valor;

  final String detalhe;

  final IconData icone;

  final VoidCallback onTap;

  final VoidCallback? onSecondaryAction;

  final IconData secondaryIcon;

  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.detalhe,
    required this.icone,
    required this.onTap,
    this.onSecondaryAction,
    this.secondaryIcon = Icons.edit_outlined,
  });
}

class _Modulo {
  final String titulo;

  final String subtitulo;

  final IconData icone;

  final VoidCallback onTap;

  const _Modulo(this.titulo, this.subtitulo, this.icone, this.onTap);
}
