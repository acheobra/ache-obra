import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'dart:typed_data';

class ChatPage extends StatefulWidget {
  final int conversaId;
  final String tituloOutroUsuario;
  final Map<String, dynamic>? orcamentoParaEnviar;

  const ChatPage({
    super.key,
    required this.conversaId,
    required this.tituloOutroUsuario,
    this.orcamentoParaEnviar,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _mensagemController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Captura o ID atual de forma dinâmica
  String get meuId => Supabase.instance.client.auth.currentUser?.id ?? '';

  bool _enviandoArquivo = false;
  bool _orcamentoEnviadoAutomaticamente = false;
  bool _notificacoesAtivas = true;
  bool _euBloqueiei = false;
  bool _fuiBloqueado = false;
  bool _marcandoMensagensComoLidas = false;
  String _outroId = '';
  String _nomeExibicao = '';

  bool _isSelecting = false;
  final Set<dynamic> _selectedMessageIds = {};
  final GlobalKey _addBtnKey = GlobalKey();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _gravandoAudio = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nomeExibicao = widget.tituloOutroUsuario;
    _carregarDadosIniciais();

    if (widget.orcamentoParaEnviar != null &&
        !_orcamentoEnviadoAutomaticamente) {
      _orcamentoEnviadoAutomaticamente = true;
      _gerarEEnviarPdfProfissionalCompletoNoChat();
    }

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _marcarMensagensComoLidas();
      }
    });
  }

  Future<void> _carregarDadosIniciais() async {
    try {
      final conversa = await Supabase.instance.client
          .from('tab_conversas')
          .select('cliente_id, outro_usuario_id, notificacoes_ativas')
          .eq('id', widget.conversaId)
          .single();

      _outroId = conversa['cliente_id'] == meuId
          ? conversa['outro_usuario_id']?.toString() ?? ''
          : conversa['cliente_id']?.toString() ?? '';

      if (mounted) {
        setState(() {
          _notificacoesAtivas = conversa['notificacoes_ativas'] ?? true;
        });
      }

      if (_outroId.isNotEmpty) {
        try {
          final resUser = await Supabase.instance.client
              .from('tab_usuarios')
              .select('usuario_nome, nome, nome_completo')
              .or('id.eq.$_outroId,user_id.eq.$_outroId')
              .maybeSingle();

          if (resUser != null) {
            final n = resUser['usuario_nome'] ??
                resUser['nome'] ??
                resUser['nome_completo'];
            if (n != null && n.toString().trim().isNotEmpty) {
              if (mounted) {
                setState(() {
                  _nomeExibicao = n.toString().trim();
                });
              }
            }
          }
        } catch (e) {
          debugPrint('Erro ao buscar nome em tab_usuarios: $e');
        }

        final meuBloqueio = await Supabase.instance.client
            .from('tab_bloqueios')
            .select('id')
            .eq('bloqueador_id', meuId)
            .eq('bloqueado_id', _outroId)
            .maybeSingle();

        final bloqueioDeles = await Supabase.instance.client
            .from('tab_bloqueios')
            .select('id')
            .eq('bloqueador_id', _outroId)
            .eq('bloqueado_id', meuId)
            .maybeSingle();

        if (mounted) {
          setState(() {
            _euBloqueiei = meuBloqueio != null;
            _fuiBloqueado = bloqueioDeles != null;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados da conversa/bloqueio: $e');
    }
  }

  Future<void> _alternarNotificacoes() async {
    final novoEstado = !_notificacoesAtivas;
    setState(() {
      _notificacoesAtivas = novoEstado;
    });

    try {
      await Supabase.instance.client.from('tab_conversas').update(
          {'notificacoes_ativas': novoEstado}).eq('id', widget.conversaId);
    } catch (e) {
      debugPrint('Erro ao atualizar notificações: $e');
      setState(() {
        _notificacoesAtivas = !novoEstado;
      });
    }
  }

  Future<void> _alternarBloqueioUsuario() async {
    try {
      if (_euBloqueiei) {
        await Supabase.instance.client
            .from('tab_bloqueios')
            .delete()
            .eq('bloqueador_id', meuId)
            .eq('bloqueado_id', _outroId);
        setState(() => _euBloqueiei = false);
      } else {
        await Supabase.instance.client.from('tab_bloqueios').insert({
          'bloqueador_id': meuId,
          'bloqueado_id': _outroId,
        });
        setState(() => _euBloqueiei = true);
      }
    } catch (e) {
      debugPrint('Erro ao alterar status de bloqueio: $e');
    }
  }

  Future<void> _dispararNotificacaoPush(String textoMensagem) async {
    if (_outroId.isEmpty) return;
    try {
      await Supabase.instance.client.functions.invoke('enviar-push', body: {
        'type': 'INSERT',
        'table': 'tab_mensagens',
        'record': {
          'conversa_id': widget.conversaId,
          'remetente_id': meuId,
          'destino_id': _outroId,
          'texto': textoMensagem,
        }
      });
    } catch (e) {
      debugPrint("Erro ao disparar push function: $e");
    }
  }

  Future<void> _gerarEEnviarPdfProfissionalCompletoNoChat() async {
    if (_enviandoArquivo) return;

    setState(() {
      _enviandoArquivo = true;
    });

    try {
      final dados = widget.orcamentoParaEnviar!;
      final bool isPedido =
          dados['tipo'] == 'pedido' || dados.containsKey('itens');

      pw.MemoryImage? imageLogo;
      try {
        final ByteData bytes =
            await rootBundle.load('assets/Logo_ache_obra.png');
        final Uint8List logoBytes = bytes.buffer.asUint8List();
        imageLogo = pw.MemoryImage(logoBytes);
      } catch (e) {
        debugPrint("Erro ao carregar a logo no chat: $e");
      }

      final pdf = pw.Document();

      if (isPedido) {
        final String titulo = dados['titulo'] ?? 'PEDIDO DE MATERIAIS';
        final List itens = dados['itens'] ?? [];
        final String dataEmissao = dados['created_at'] != null
            ? "${DateTime.parse(dados['created_at']).day}/${DateTime.parse(dados['created_at']).month}/${DateTime.parse(dados['created_at']).year}"
            : "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";

        pdf.addPage(
          pw.MultiPage(
            pageFormat: pw_pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return [
                pw.Header(
                  level: 0,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('PEDIDO DE MATERIAIS',
                              style: pw.TextStyle(
                                  fontSize: 18,
                                  fontWeight: pw.FontWeight.bold,
                                  color: pw_pdf.PdfColors.orange800)),
                          pw.SizedBox(height: 5),
                          pw.Text(titulo,
                              style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text('Data: $dataEmissao',
                              style: const pw.TextStyle(fontSize: 11)),
                        ],
                      ),
                      if (imageLogo != null)
                        pw.Image(imageLogo, width: 80, height: 80)
                      else
                        pw.SizedBox(width: 80, height: 80),
                    ],
                  ),
                ),
                pw.SizedBox(height: 15),
                pw.Text('ITENS DO PEDIDO:',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.blueGrey900)),
                pw.Divider(color: pw_pdf.PdfColors.orange800),
                ...itens.map((it) => pw.Paragraph(
                    text:
                        '• ${it['produto']} | Qtd: ${it['quantidade']} ${it['observacao'] != null && it['observacao'].toString().isNotEmpty ? '\n Obs: ${it['observacao']}' : ''}')),
              ];
            },
          ),
        );

        final Uint8List pdfBytes = await pdf.save();
        final String fileName =
            "Pedido_${titulo.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf";

        await _enviarArquivoParaSupabase(
          fileBytes: pdfBytes,
          fileName: fileName,
          tipo: 'documento',
        );
      } else {
        final String profNome = dados['prof_nome'] ?? '';
        final String profCpfCnpj = dados['prof_cpf_cnpj'] ?? '';
        final String profEndereco = dados['prof_endereco'] ?? '';
        final String profContato = dados['prof_contato'] ?? '';

        final String cliNome = dados['cli_nome'] ?? 'Cliente';
        final String cliCpf = dados['cli_cpf'] ?? '';
        final String cliTelefone = dados['cli_telefone'] ?? '';
        final String cliEmail = dados['cli_email'] ?? '';

        final String localObra = dados['local_obra'] ?? '';
        final String dataEmissao = dados['data_emissao'] ??
            "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
        final String validade = dados['validade'] ?? '10 dias';

        final String descricaoServico = dados['descricao_servico'] ?? '';
        final String quantitativos = dados['quantitativos'] ?? '';
        final String maoDeObra = dados['mao_de_obra'] ?? '';

        final String modeloCobranca = dados['modelo_cobranca'] ?? '';
        final String precoTotal = dados['preco_total'] ?? '';
        final String insumos = dados['insumos'] ?? '';
        final String respMateriais = dados['resp_materiais'] ?? '';

        final String prazoExecucao = dados['prazo_execucao'] ?? '';
        final String dataInicio = dados['data_inicio'] ?? '';
        final String impactoClimatico = dados['impacto_climatico'] ?? '';

        final String formaPagamento = dados['forma_pagamento'] ?? '';
        final String parcelamento = dados['parcelamento'] ?? '';
        final String servicosAdicionais = dados['servicos_adicionais'] ?? '';

        pdf.addPage(
          pw.MultiPage(
            pageFormat: pw_pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return [
                pw.Header(
                  level: 0,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('ORÇAMENTO PROFISSIONAL',
                              style: pw.TextStyle(
                                  fontSize: 18,
                                  fontWeight: pw.FontWeight.bold,
                                  color: pw_pdf.PdfColors.orange800)),
                          pw.SizedBox(height: 5),
                          pw.Text('Data: $dataEmissao',
                              style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                      if (imageLogo != null)
                        pw.Image(imageLogo, width: 80, height: 80)
                      else
                        pw.SizedBox(width: 80, height: 80),
                    ],
                  ),
                ),
                pw.SizedBox(height: 15),
                pw.Text('1. DADOS DE IDENTIFICAÇÃO',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.blueGrey900)),
                pw.Divider(color: pw_pdf.PdfColors.orange800),
                pw.Paragraph(
                    text:
                        '• Profissional: $profNome ${profCpfCnpj.isNotEmpty ? '(CPF/CNPJ: $profCpfCnpj)' : ''}\nEndereço: $profEndereco | Contato: $profContato'),
                pw.Paragraph(
                    text:
                        '• Cliente: $cliNome ${cliCpf.isNotEmpty ? '(CPF: $cliCpf)' : ''}\nTelefone: $cliTelefone | E-mail: $cliEmail'),
                pw.Paragraph(
                    text:
                        '• Local da Obra: $localObra\n• Validade da Proposta: $validade'),
                pw.SizedBox(height: 10),
                pw.Text('2. ESCOPO DO SERVIÇO',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.blueGrey900)),
                pw.Divider(color: pw_pdf.PdfColors.orange800),
                pw.Paragraph(text: '• Descrição Detalhada:\n$descricaoServico'),
                pw.Paragraph(text: '• Quantitativos e Medidas: $quantitativos'),
                pw.Paragraph(text: '• Mão de Obra: $maoDeObra'),
                pw.SizedBox(height: 10),
                pw.Text('3. CUSTOS E VALORES',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.blueGrey900)),
                pw.Divider(color: pw_pdf.PdfColors.orange800),
                pw.Paragraph(text: '• Modelo de Cobrança: $modeloCobranca'),
                pw.Paragraph(text: '• Valor Total/Unitário: $precoTotal'),
                pw.Paragraph(text: '• Insumos Inclusos: $insumos'),
                pw.Paragraph(
                    text: '• Responsabilidade dos Materiais:\n$respMateriais'),
                pw.SizedBox(height: 10),
                pw.Text('4. PRAZOS E CRONOGRAMA',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.blueGrey900)),
                pw.Divider(color: pw_pdf.PdfColors.orange800),
                pw.Paragraph(text: '• Prazo de Execução: $prazoExecucao'),
                pw.Paragraph(text: '• Data Prevista de Início: $dataInicio'),
                pw.Paragraph(text: '• Observação Climática: $impactoClimatico'),
                pw.SizedBox(height: 10),
                pw.Text('5. CONDIÇÕES DE PAGAMENTO E TERMOS',
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.blueGrey900)),
                pw.Divider(color: pw_pdf.PdfColors.orange800),
                pw.Paragraph(text: '• Forma de Pagamento: $formaPagamento'),
                pw.Paragraph(
                    text: '• Condições de Parcelamento: $parcelamento'),
                pw.Paragraph(
                    text: '• Serviços Adicionais:\n$servicosAdicionais'),
              ];
            },
          ),
        );

        final Uint8List pdfBytes = await pdf.save();
        final String fileName =
            "Orcamento_${cliNome.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf";

        await _enviarArquivoParaSupabase(
          fileBytes: pdfBytes,
          fileName: fileName,
          tipo: 'documento',
        );
      }
    } catch (e) {
      debugPrint('Erro ao gerar/enviar PDF no chat: $e');
      if (mounted) {
        setState(() {
          _enviandoArquivo = false;
        });
      }
    }
  }

  Future<void> _marcarMensagensComoLidas() async {
    // Evita várias atualizações simultâneas disparadas pelo StreamBuilder.
    if (_marcandoMensagensComoLidas || meuId.isEmpty) return;

    _marcandoMensagensComoLidas = true;
    try {
      await Supabase.instance.client
          .from('tab_mensagens')
          .update({'lida': true})
          .eq('conversa_id', widget.conversaId)
          .neq('remetente_id', meuId)
          .eq('lida', false);
    } catch (e) {
      debugPrint('Erro ao marcar mensagens como lidas: $e');
    } finally {
      _marcandoMensagensComoLidas = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ao voltar para o app com esta conversa aberta, limpa qualquer mensagem
    // que tenha chegado enquanto o aplicativo estava em segundo plano.
    if (state == AppLifecycleState.resumed) {
      _marcarMensagensComoLidas();
    }
  }

  final List<String> _emojisRapidos = [
    '👍',
    '👎',
    '👏',
    '🙏',
    '🤝',
    '✅',
    '❌',
    '⭐',
    '🔥',
    '💡',
    '🏗️',
    '🔨',
    '🔧',
    '🔩',
    '🧱',
    '🏠',
    '🏢',
    '📏',
    '📐',
    '🎨',
    '💰',
    '💳',
    '📅',
    '⏰',
    '📍',
    '🚗',
    '🚚',
    '📦',
    '⚠️',
    '💬',
    '😊',
    '😎',
    '😉',
    '1️⃣',
    '2️⃣',
    '3️⃣'
  ];

  void _inserirEmoji(String emoji) {
    final text = _mensagemController.text;
    final selection = _mensagemController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      _mensagemController.text = newText;
      _mensagemController.selection = TextSelection.collapsed(
        offset: selection.start + emoji.length,
      );
    } else {
      _mensagemController.text = text + emoji;
      _mensagemController.selection = TextSelection.collapsed(
        offset: _mensagemController.text.length,
      );
    }
  }

  void _mostrarSeletorEmojis() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF253c59),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: 280,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Emojis',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10),
                  itemCount: _emojisRapidos.length,
                  itemBuilder: (context, index) {
                    final emoji = _emojisRapidos[index];
                    return InkWell(
                      onTap: () {
                        _inserirEmoji(emoji);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 26))),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _abrirLinkMensagem(String link) async {
    try {
      String url = link.trim();

      // Permite também links digitados como www.site.com.br sem https://.
      if (!url.toLowerCase().startsWith('http://') &&
          !url.toLowerCase().startsWith('https://')) {
        url = 'https://$url';
      }

      final uri = Uri.tryParse(url);
      if (uri == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link inválido.')),
          );
        }
        return;
      }

      final abriu = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!abriu && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    } catch (e) {
      debugPrint('Erro ao abrir link da mensagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    }
  }

  Widget _formatarTextoMensagem(String texto, bool souEu) {
    final TextStyle estiloBase = const TextStyle(color: Colors.white);
    final TextStyle estiloLink = estiloBase.copyWith(
      color: Colors.lightBlueAccent,
      decoration: TextDecoration.underline,
      decorationColor: Colors.lightBlueAccent,
    );

    final List<InlineSpan> spans = [];

    // Reconhece links com http://, https:// e também www.
    final RegExp linkRegExp = RegExp(
      r'((?:https?:\/\/|www\.)[^\s<>]+)',
      caseSensitive: false,
    );

    // Mantém a formatação que o chat já possuía: *negrito*, _itálico_ e ~riscado~.
    final RegExp formatRegExp = RegExp(r'(\*[^*]+\*|_[^_]+_|~[^~]+~)');

    void adicionarTrechoFormatado(String trecho) {
      int ultimoIndex = 0;

      for (final Match match in formatRegExp.allMatches(trecho)) {
        if (match.start > ultimoIndex) {
          spans.add(TextSpan(
            text: trecho.substring(ultimoIndex, match.start),
            style: estiloBase,
          ));
        }

        final String marcado = match.group(0)!;
        final String conteudo = marcado.substring(1, marcado.length - 1);

        if (marcado.startsWith('*') && marcado.endsWith('*')) {
          spans.add(TextSpan(
            text: conteudo,
            style: estiloBase.copyWith(fontWeight: FontWeight.bold),
          ));
        } else if (marcado.startsWith('_') && marcado.endsWith('_')) {
          spans.add(TextSpan(
            text: conteudo,
            style: estiloBase.copyWith(fontStyle: FontStyle.italic),
          ));
        } else if (marcado.startsWith('~') && marcado.endsWith('~')) {
          spans.add(TextSpan(
            text: conteudo,
            style: estiloBase.copyWith(decoration: TextDecoration.lineThrough),
          ));
        }

        ultimoIndex = match.end;
      }

      if (ultimoIndex < trecho.length) {
        spans.add(TextSpan(
          text: trecho.substring(ultimoIndex),
          style: estiloBase,
        ));
      }
    }

    int ultimoIndex = 0;

    for (final Match match in linkRegExp.allMatches(texto)) {
      if (match.start > ultimoIndex) {
        adicionarTrechoFormatado(texto.substring(ultimoIndex, match.start));
      }

      String linkExibido = match.group(0)!;
      String linkAbrir = linkExibido;

      // Não inclui pontuação comum colocada imediatamente depois do link.
      while (linkExibido.isNotEmpty &&
          RegExp(r'[.,;:!?]$').hasMatch(linkExibido)) {
        linkExibido = linkExibido.substring(0, linkExibido.length - 1);
      }

      linkAbrir = linkExibido;

      spans.add(
        TextSpan(
          text: linkExibido,
          style: estiloLink,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _abrirLinkMensagem(linkAbrir),
        ),
      );

      // Recoloca eventual pontuação retirada do final do link.
      final String original = match.group(0)!;
      if (original.length > linkExibido.length) {
        spans.add(TextSpan(
          text: original.substring(linkExibido.length),
          style: estiloBase,
        ));
      }

      ultimoIndex = match.end;
    }

    if (ultimoIndex < texto.length) {
      adicionarTrechoFormatado(texto.substring(ultimoIndex));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: texto, style: estiloBase));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  void _enviarMensagemTexto() async {
    if (_euBloqueiei || _fuiBloqueado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_euBloqueiei
                ? "Você bloqueou este usuário. Desbloqueie para enviar mensagens."
                : "Esta conversa está indisponível.")),
      );
      return;
    }

    final idRemetente = meuId;
    if (idRemetente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sessão expirada. Faça login novamente."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;

    if (_outroId.isEmpty) {
      await _carregarDadosIniciais();
    }

    _mensagemController.clear();

    try {
      // CORREÇÃO APLICADA AQUI: Incluindo conversa_id e remetente_id explicitamente para acionar o push corretamente
      await Supabase.instance.client.from('tab_mensagens').insert({
        'conversa_id': widget.conversaId,
        'remetente_id': idRemetente,
        'texto': texto,
        'tipo_arquivo': 'texto',
        'lida': false,
      });

      await _dispararNotificacaoPush(texto);
    } catch (e) {
      debugPrint('Erro ao enviar mensagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao enviar mensagem: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _mostrarOpcoesAnexo() async {
    final RenderBox? renderBox =
        _addBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);

    final String? escolha = await showMenu<String>(
      context: context,
      color: const Color(0xFF253c59),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
          position.dx, position.dy - 260, position.dx + 250, position.dy),
      items: const [
        PopupMenuItem(
            value: 'galeria',
            child: Row(children: [
              Icon(Icons.photo_library, color: Color(0xFFFF8C00)),
              SizedBox(width: 10),
              Text('Galeria de Fotos', style: TextStyle(color: Colors.white))
            ])),
        PopupMenuItem(
            value: 'camera_foto',
            child: Row(children: [
              Icon(Icons.camera_alt, color: Color(0xFFFF8C00)),
              SizedBox(width: 10),
              Text('Tirar Foto (Câmera)', style: TextStyle(color: Colors.white))
            ])),
        PopupMenuItem(
            value: 'video_galeria',
            child: Row(children: [
              Icon(Icons.video_library, color: Color(0xFFFF8C00)),
              SizedBox(width: 10),
              Text('Vídeo da Galeria', style: TextStyle(color: Colors.white))
            ])),
        PopupMenuItem(
            value: 'camera_video',
            child: Row(children: [
              Icon(Icons.videocam, color: Color(0xFFFF8C00)),
              SizedBox(width: 10),
              Text('Gravar Vídeo (Câmera)',
                  style: TextStyle(color: Colors.white))
            ])),
        PopupMenuItem(
            value: 'documento',
            child: Row(children: [
              Icon(Icons.insert_drive_file, color: Color(0xFFFF8C00)),
              SizedBox(width: 10),
              Text('Documento (PDF, Word, etc.)',
                  style: TextStyle(color: Colors.white))
            ])),
      ],
    );

    if (escolha != null) {
      if (escolha == 'galeria')
        _enviarArquivoMidia(fonte: ImageSource.gallery, isVideo: false);
      else if (escolha == 'camera_foto')
        _enviarArquivoMidia(fonte: ImageSource.camera, isVideo: false);
      else if (escolha == 'video_galeria')
        _enviarArquivoMidia(fonte: ImageSource.gallery, isVideo: true);
      else if (escolha == 'camera_video')
        _enviarArquivoMidia(fonte: ImageSource.camera, isVideo: true);
      else if (escolha == 'documento') _enviarDocumento();
    }
  }

  Future<void> _enviarArquivoMidia(
      {required ImageSource fonte, required bool isVideo}) async {
    if (_enviandoArquivo || _euBloqueiei || _fuiBloqueado) return;
    setState(() => _enviandoArquivo = true);
    try {
      final picker = ImagePicker();
      XFile? arquivo = isVideo
          ? await picker.pickVideo(source: fonte)
          : await picker.pickImage(source: fonte);
      if (arquivo == null) {
        setState(() => _enviandoArquivo = false);
        return;
      }
      final bytes = await arquivo.readAsBytes();
      await _enviarArquivoParaSupabase(
          fileBytes: bytes,
          fileName: arquivo.name,
          tipo: isVideo ? 'video' : 'foto');
    } catch (e) {
      debugPrint('Erro ao selecionar mídia: $e');
      setState(() => _enviandoArquivo = false);
    }
  }

  Future<void> _enviarDocumento() async {
    if (_enviandoArquivo || _euBloqueiei || _fuiBloqueado) return;
    setState(() => _enviandoArquivo = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'txt',
            'zip'
          ]);
      if (result == null || result.files.single.name.isEmpty) {
        setState(() => _enviandoArquivo = false);
        return;
      }
      Uint8List? bytes;
      if (kIsWeb)
        bytes = result.files.single.bytes;
      else if (result.files.single.path != null)
        bytes = await File(result.files.single.path!).readAsBytes();
      if (bytes != null) {
        await _enviarArquivoParaSupabase(
            fileBytes: bytes,
            fileName: result.files.single.name,
            tipo: 'documento');
      } else {
        setState(() => _enviandoArquivo = false);
      }
    } catch (e) {
      debugPrint('Erro ao selecionar documento: $e');
      setState(() => _enviandoArquivo = false);
    }
  }

  Future<void> _abrirDocumento(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri))
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      else
        debugPrint('Não foi possível abrir o documento: $url');
    } catch (e) {
      debugPrint('Erro ao abrir documento: $e');
    }
  }

  Future<void> _enviarArquivoParaSupabase(
      {required Uint8List fileBytes,
      required String fileName,
      required String tipo}) async {
    final idRemetente = meuId;
    if (idRemetente.isEmpty) return;

    try {
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final storagePath = 'chat_uploads/$uniqueName';
      await Supabase.instance.client.storage
          .from('chat_bucket')
          .uploadBinary(storagePath, fileBytes);
      final publicUrl = Supabase.instance.client.storage
          .from('chat_bucket')
          .getPublicUrl(storagePath);
      String descricaoTexto = tipo == 'foto'
          ? '📷 Foto'
          : tipo == 'video'
              ? '🎥 Vídeo'
              : fileName;

      // CORREÇÃO APLICADA AQUI TAMBÉM: Incluindo conversa_id e remetente_id no envio de arquivos/mídias
      await Supabase.instance.client.from('tab_mensagens').insert({
        'conversa_id': widget.conversaId,
        'remetente_id': idRemetente,
        'texto': descricaoTexto,
        'arquivo_url': publicUrl,
        'tipo_arquivo': tipo,
        'lida': false,
      });
      await _dispararNotificacaoPush(descricaoTexto);
    } catch (e) {
      debugPrint('Erro ao enviar arquivo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao enviar arquivo: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoArquivo = false);
    }
  }

  Future<void> _iniciarGravacaoAudio() async {
    if (_gravandoAudio || _enviandoArquivo || _euBloqueiei || _fuiBloqueado)
      return;
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path =
            '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _gravandoAudio = true);
      }
    } catch (e) {
      debugPrint('Erro ao iniciar gravação: $e');
    }
  }

  Future<void> _pararEEnviarAudio() async {
    if (!_gravandoAudio) return;
    setState(() {
      _gravandoAudio = false;
      _enviandoArquivo = true;
    });
    try {
      final path = await _audioRecorder.stop();
      if (path == null) {
        setState(() => _enviandoArquivo = false);
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        setState(() => _enviandoArquivo = false);
        return;
      }
      final bytes = await file.readAsBytes();
      await _enviarArquivoParaSupabase(
          fileBytes: bytes,
          fileName: 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
          tipo: 'audio');
    } catch (e) {
      debugPrint('Erro ao enviar áudio: $e');
      setState(() => _enviandoArquivo = false);
    }
  }

  String _formatarDataMensagem(String? dataIso) {
    if (dataIso == null) return '';
    final dataUtc = DateTime.parse(dataIso).toLocal();
    final hoje = DateTime.now();
    final diff = DateTime(hoje.year, hoje.month, hoje.day)
        .difference(DateTime(dataUtc.year, dataUtc.month, dataUtc.day))
        .inDays;
    final hora = DateFormat('HH:mm').format(dataUtc);
    if (diff == 0)
      return 'Hoje às $hora';
    else if (diff == 1)
      return 'Ontem às $hora';
    else
      return '${DateFormat('dd/MM/yyyy').format(dataUtc)} às $hora';
  }

  void _abrirVisualizadorImagem(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(child: Image.network(url)),
            Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context))),
          ],
        ),
      ),
    );
  }

  void _abrirPlayerDeVideo(String url) {
    showDialog(
        context: context,
        builder: (context) => _VideoPlayerModal(videoUrl: url));
  }

  void _abrirPlayerDeAudio(String url) {
    showDialog(
        context: context,
        builder: (context) => _AudioPlayerModal(audioUrl: url));
  }

  void _confirmarExcluirConversa() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF253c59),
        title: const Text('Excluir Conversa',
            style: TextStyle(color: Colors.white)),
        content: const Text('Deseja realmente apagar esta conversa inteira?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Não', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await Supabase.instance.client
                    .from('tab_mensagens')
                    .delete()
                    .eq('conversa_id', widget.conversaId);
                await Supabase.instance.client
                    .from('tab_conversas')
                    .delete()
                    .eq('id', widget.conversaId);
                if (mounted) Navigator.pop(context, true);
              } catch (e) {
                debugPrint('Erro ao excluir conversa: $e');
              }
            },
            child: const Text('Sim', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmarExcluirMensagensSelecionadas() {
    if (_selectedMessageIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF253c59),
        title: const Text('Excluir Mensagens',
            style: TextStyle(color: Colors.white)),
        content: Text(
            'Deseja apagar ${_selectedMessageIds.length} mensagem(ns) selecionada(s)?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Não', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await Supabase.instance.client
                    .from('tab_mensagens')
                    .delete()
                    .inFilter('id', _selectedMessageIds.toList());
                setState(() {
                  _isSelecting = false;
                  _selectedMessageIds.clear();
                });
              } catch (e) {
                debugPrint('Erro ao excluir mensagens: $e');
              }
            },
            child: const Text('Sim', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // Garante que, antes de sair desta conversa, todas as mensagens
  // recebidas já exibidas sejam persistidas como lidas no Supabase.
  // Assim, a tela anterior/feed recalcula o contador com o banco atualizado.
  Future<void> _sairDoChat() async {
    await _marcarMensagensComoLidas();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<bool> _tratarVoltarSistema() async {
    await _marcarMensagensComoLidas();
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mensagemController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _tratarVoltarSistema,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A2C42),
        appBar: AppBar(
          backgroundColor: const Color(0xFF253c59),
          leading: _isSelecting
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _isSelecting = false;
                      _selectedMessageIds.clear();
                    });
                  })
              : IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _sairDoChat,
                ),
          title: _isSelecting
              ? Text('${_selectedMessageIds.length} selecionada(s)',
                  style: const TextStyle(color: Colors.white, fontSize: 16))
              : GestureDetector(
                  onLongPress: _confirmarExcluirConversa,
                  child: Text(_nomeExibicao,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: _isSelecting
              ? [
                  IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: _confirmarExcluirMensagensSelecionadas),
                ]
              : [
                  IconButton(
                    icon: Icon(
                      _notificacoesAtivas
                          ? Icons.notifications
                          : Icons.notifications_off,
                      color: _notificacoesAtivas
                          ? Colors.white
                          : Colors.orangeAccent,
                    ),
                    onPressed: _alternarNotificacoes,
                    tooltip: _notificacoesAtivas
                        ? 'Silenciar conversa'
                        : 'Ativar som da conversa',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'excluir')
                        _confirmarExcluirConversa();
                      else if (value == 'bloquear') _alternarBloqueioUsuario();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: 'excluir', child: Text('Excluir Conversa')),
                      PopupMenuItem(
                          value: 'bloquear',
                          child: Text(_euBloqueiei
                              ? 'Desbloquear Usuário'
                              : 'Bloquear Usuário')),
                    ],
                  ),
                ],
        ),
        body: Column(
          children: [
            if (_enviandoArquivo || _gravandoAudio)
              LinearProgressIndicator(
                  color: _gravandoAudio ? Colors.red : const Color(0xFFFF8C00)),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('tab_mensagens')
                    .stream(primaryKey: ['id'])
                    .eq('conversa_id', widget.conversaId)
                    .order('created_at', ascending: false),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFFF8C00)));

                  final mensagens = snapshot.data!.where((msg) {
                    if (_euBloqueiei || _fuiBloqueado) {
                      if (msg['remetente_id'] != meuId) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  // IMPORTANTE: o código antigo marcava como lidas somente uma vez,
                  // 1 segundo após abrir a tela. Se uma nova mensagem chegasse com o
                  // chat já aberto, ela continuava lida=false e inflava o contador.
                  final temMensagemRecebidaNaoLida = snapshot.data!.any((msg) =>
                      msg['remetente_id'] != meuId && msg['lida'] != true);

                  if (temMensagemRecebidaNaoLida) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _marcarMensagensComoLidas();
                      }
                    });
                  }

                  if (mensagens.isEmpty)
                    return const Center(
                        child: Text(
                            "Nenhuma mensagem ainda.\nInicie a conversa!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54)));

                  return ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: mensagens.length,
                    itemBuilder: (context, index) {
                      final msg = mensagens[index];
                      final msgId = msg['id'];
                      final souEu = msg['remetente_id'] == meuId;
                      final tipoArquivo = msg['tipo_arquivo'];
                      final arquivoUrl = msg['arquivo_url'];
                      final bool lida = msg['lida'] == true;
                      final bool isSelected =
                          _selectedMessageIds.contains(msgId);
                      final dataFormatada =
                          _formatarDataMensagem(msg['created_at']);

                      return Align(
                        alignment: souEu
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () {
                            setState(() {
                              if (!_isSelecting) {
                                _isSelecting = true;
                                _selectedMessageIds.add(msgId);
                              } else {
                                if (isSelected) {
                                  _selectedMessageIds.remove(msgId);
                                  if (_selectedMessageIds.isEmpty)
                                    _isSelecting = false;
                                } else
                                  _selectedMessageIds.add(msgId);
                              }
                            });
                          },
                          onTap: () {
                            if (_isSelecting) {
                              setState(() {
                                if (isSelected) {
                                  _selectedMessageIds.remove(msgId);
                                  if (_selectedMessageIds.isEmpty)
                                    _isSelecting = false;
                                } else
                                  _selectedMessageIds.add(msgId);
                              });
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.orange.withOpacity(0.4)
                                  : (souEu
                                      ? const Color(0xFF334155)
                                      : const Color(0xFF253c59)),
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected
                                  ? Border.all(color: Colors.orange, width: 2)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (arquivoUrl != null &&
                                    arquivoUrl.toString().isNotEmpty) ...[
                                  if (tipoArquivo == 'foto')
                                    Center(
                                        child: GestureDetector(
                                            onTap: () {
                                              if (!_isSelecting)
                                                _abrirVisualizadorImagem(
                                                    arquivoUrl);
                                            },
                                            child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(arquivoUrl,
                                                    height: 150,
                                                    width: 200,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context,
                                                            error,
                                                            stackTrace) =>
                                                        const Text(
                                                            'Erro ao carregar imagem',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white54))))))
                                  else if (tipoArquivo == 'video')
                                    Center(
                                        child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.black45,
                                                foregroundColor: Colors.white,
                                                elevation: 0),
                                            onPressed: () {
                                              if (!_isSelecting)
                                                _abrirPlayerDeVideo(arquivoUrl);
                                            },
                                            icon: const Icon(
                                                Icons.play_circle_fill,
                                                color: Colors.orange),
                                            label:
                                                const Text('Assistir Vídeo')))
                                  else if (tipoArquivo == 'audio')
                                    Center(
                                        child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.black45,
                                                foregroundColor: Colors.white,
                                                elevation: 0),
                                            onPressed: () {
                                              if (!_isSelecting)
                                                _abrirPlayerDeAudio(arquivoUrl);
                                            },
                                            icon: const Icon(
                                                Icons.play_circle_fill,
                                                color: Colors.orange),
                                            label: const Text('Ouvir Áudio')))
                                  else
                                    InkWell(
                                        onTap: () {
                                          if (!_isSelecting)
                                            _abrirDocumento(arquivoUrl);
                                        },
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.picture_as_pdf,
                                                  color: Colors.orangeAccent),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                  child: Text(
                                                      msg['texto'] ??
                                                          'Documento.pdf',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          decoration:
                                                              TextDecoration
                                                                  .underline)))
                                            ])),
                                  const SizedBox(height: 6),
                                ],
                                if (tipoArquivo == 'texto' ||
                                    tipoArquivo == null)
                                  _formatarTextoMensagem(
                                      msg['texto'] ?? '', souEu),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(dataFormatada,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500)),
                                    if (souEu) ...[
                                      const SizedBox(width: 6),
                                      Icon(lida ? Icons.done_all : Icons.done,
                                          size: 16,
                                          color: lida
                                              ? Colors.lightBlueAccent
                                              : Colors.white54)
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: const Color(0xFF253c59),
              child: (_euBloqueiei || _fuiBloqueado)
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                          child: Text(
                              _euBloqueiei
                                  ? "Você bloqueou este usuário."
                                  : "Esta conversa está indisponível.",
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontStyle: FontStyle.italic))))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                            key: _addBtnKey,
                            icon:
                                const Icon(Icons.add, color: Color(0xFFFF8C00)),
                            onPressed:
                                _enviandoArquivo ? null : _mostrarOpcoesAnexo),
                        IconButton(
                            icon: const Icon(Icons.emoji_emotions_outlined,
                                color: Color(0xFFFF8C00)),
                            onPressed: _mostrarSeletorEmojis),
                        Expanded(
                            child: TextField(
                                controller: _mensagemController,
                                style: const TextStyle(color: Colors.white),
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                decoration: const InputDecoration(
                                    hintText: "Digite sua mensagem...",
                                    hintStyle: TextStyle(
                                        color: Colors.white54, fontSize: 13),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10)))),
                        Listener(
                          onPointerDown: (_) => _iniciarGravacaoAudio(),
                          onPointerUp: (_) => _pararEEnviarAudio(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: EdgeInsets.all(_gravandoAudio ? 16 : 12),
                            decoration: BoxDecoration(
                                color: _gravandoAudio
                                    ? Colors.red.withOpacity(0.4)
                                    : Colors.transparent,
                                shape: BoxShape.circle),
                            child: Icon(_gravandoAudio ? Icons.mic : Icons.mic,
                                color: _gravandoAudio
                                    ? Colors.redAccent
                                    : const Color(0xFFFF8C00),
                                size: _gravandoAudio ? 42 : 34),
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.send,
                                color: Color(0xFFFF8C00)),
                            onPressed:
                                _enviandoArquivo ? null : _enviarMensagemTexto),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerModal extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerModal({required this.videoUrl});
  @override
  State<_VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<_VideoPlayerModal> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(alignment: Alignment.center, children: [
          _isInitialized
              ? Center(
                  child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller)))
              : const CircularProgressIndicator(color: Color(0xFFFF8C00)),
          Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context))),
          if (_isInitialized)
            Positioned(
                bottom: 40,
                child: FloatingActionButton(
                    backgroundColor: const Color(0xFFFF8C00),
                    child: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    })),
        ]));
  }
}

class _AudioPlayerModal extends StatefulWidget {
  final String audioUrl;
  const _AudioPlayerModal({required this.audioUrl});
  @override
  State<_AudioPlayerModal> createState() => _AudioPlayerModalState();
}

class _AudioPlayerModalState extends State<_AudioPlayerModal> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.audioUrl))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF253c59),
      title: const Text('Ouvir Áudio', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _isInitialized
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: const Color(0xFFFF8C00),
                        size: 60),
                    onPressed: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    })
              ])
            : const CircularProgressIndicator(color: Color(0xFFFF8C00)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Fechar', style: TextStyle(color: Colors.white54)))
      ],
    );
  }
}
