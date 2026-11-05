import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../main.dart';
import 'feed_page.dart';
import 'planos_usuario_page.dart';
import 'orcamento_page.dart';
import 'lista_orcamentos_page.dart';
import 'pedido_materiais_page.dart';

class ClienteHomePage extends StatefulWidget {
  final int abaInicial;
  const ClienteHomePage({super.key, this.abaInicial = 0});

  @override
  State<ClienteHomePage> createState() => _ClienteHomePageState();
}

class _ClienteHomePageState extends State<ClienteHomePage> {
  late int _abaAtiva;

  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _senhaAntigaController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();

  final List<String> _listaEstados = [
    "AC",
    "AL",
    "AM",
    "AP",
    "BA",
    "CE",
    "DF",
    "ES",
    "GO",
    "MA",
    "MG",
    "MS",
    "MT",
    "PA",
    "PB",
    "PE",
    "PI",
    "PR",
    "RJ",
    "RN",
    "RO",
    "RR",
    "RS",
    "SC",
    "SE",
    "SP",
    "TO"
  ];

  String? _estadoSelecionado;
  String? _cidadeSelecionada;
  String _nomeExibicao = "";
  String? _fotoUrl;
  File? _novaImagemArquivo;
  bool _enviandoFoto = false;

  List<String> _listaCidades = [];
  bool _carregandoCidades = false;
  bool _verificandoAcesso = true;

  String? _tipoEscolhido;
  bool _isLoadingProfissoes = true;
  bool _isSalvandoDemanda = false;
  List<dynamic> _listaProfissoesBanco = [];
  final Map<String, bool> _servicosSelecionados = {};

  String? _estadoServico;
  String? _cidadeServico;
  List<String> _listaCidadesServico = [];
  bool _carregandoCidadesServico = false;

  String _tipoUsuarioLogado = 'cliente';
  String _nomePlanoAtivo = 'gratis';

  List<String> _fotosTrabalhosUrls = [];
  List<String> _videosTrabalhosUrls = [];
  int _limiteFotosPlano = 1;
  int _limiteVideosPlano = 1;
  int _limiteServicosPlano = 1;
  bool _temPermissaoFacebook = false;
  bool _temPermissaoInstagram = false;
  bool _enviandoFotoTrabalho = false;
  bool _enviandoVideoTrabalho = false;

  int _qtdePostagemPermitida = 1;
  List<Map<String, dynamic>> _minhasDemandas = [];
  bool _carregandoDemandas = true;

  String _modoTelaAba1 = 'lista';
  String? _idDemandaEmEdicao;

  final _bairroController = TextEditingController();
  final _descricaoController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _abaAtiva = widget.abaInicial;
    _verificarAcessoCarregarDados();
    _carregarProfissoesDoBanco();
  }

  Future<void> _verificarAcessoCarregarDados() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _redirecionarLogin();
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('tab_usuarios')
          .select()
          .eq('id', user.id)
          .single();

      final tipoUsuario = (data['usuario_tipo'] ?? data['tipo'] ?? 'cliente')
          .toString()
          .trim()
          .toLowerCase();

      String planoAtual =
          (data['nome_plano_ativo'] ?? '').toString().trim().toLowerCase();
      if (planoAtual.isEmpty) planoAtual = 'gratis';

      setState(() {
        _tipoUsuarioLogado = tipoUsuario;
        _nomePlanoAtivo = planoAtual;
        _nomeController.text = data['usuario_nome'] ?? '';
        _nomeExibicao = data['usuario_nome'] ?? 'Usuário';
        _emailController.text = data['email'] ?? '';
        _whatsappController.text = data['whatsapp'] ?? '';
        _facebookController.text = data['link_facebook'] ?? '';
        _instagramController.text = data['link_instagram'] ?? '';
        _estadoSelecionado = data['estado'];
        _cidadeSelecionada = data['cidade'];
        _fotoUrl = data['foto_url'];
        _estadoServico = data['estado'];
        _cidadeServico = data['cidade'];

        if (_tipoUsuarioLogado == 'profissional' ||
            _tipoUsuarioLogado == 'arquiteto' ||
            _tipoUsuarioLogado == 'engenheiro') {
          _tipoEscolhido = 'Profissional';
        }

        _verificandoAcesso = false;
      });

      if (_estadoSelecionado != null) {
        await _buscarCidades(_estadoSelecionado!, manterCidadeAtual: true);
      }
      if (_estadoServico != null) {
        await _buscarCidadesServico(_estadoServico!, manterCidadeAtual: true);
      }

      await _carregarConfiguracaoPlano(planoAtual);
      await _carregarMinhasDemandas(user.id);
    } catch (e) {
      debugPrint('Erro ao verificar acesso: $e');
      _redirecionarLogin();
    }
  }

  Future<void> _carregarConfiguracaoPlano(String nomePlanoAtivo) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      String planoBusca = nomePlanoAtivo.trim().toLowerCase();
      if (planoBusca.isEmpty) planoBusca = 'gratis';

      Map<String, dynamic>? planData;
      bool planoManualCarregado = false;

      // ================================================================
      // 1) PLANO MANUAL
      // ================================================================
      // O plano manual pertence ao usuário, por isso a busca é feita por
      // usuario_id e somente entre planos ativos. Isso evita interferir
      // nos planos comerciais da tab_planos.
      //
      // Também validamos data_fim quando ela estiver preenchida. Se o
      // plano manual estiver vencido, ele é ignorado nesta tela.
      try {
        final responseManual = await Supabase.instance.client
            .from('tab_planos_manuais')
            .select()
            .eq('usuario_id', user.id)
            .eq('ativo', true)
            .order('data_inicio', ascending: false)
            .limit(1);

        if (responseManual.isNotEmpty) {
          final manual = Map<String, dynamic>.from(responseManual.first as Map);

          bool dentroDaValidade = true;
          final dataFimRaw = manual['data_fim'];

          if (dataFimRaw != null && dataFimRaw.toString().trim().isNotEmpty) {
            final dataFim = DateTime.tryParse(dataFimRaw.toString());
            if (dataFim != null && DateTime.now().isAfter(dataFim)) {
              dentroDaValidade = false;
            }
          }

          final nomeManual =
              (manual['nome_plano'] ?? '').toString().trim().toLowerCase();

          // O plano manual só assume os limites quando ele é realmente o
          // plano ativo registrado para este usuário.
          if (dentroDaValidade &&
              nomeManual.isNotEmpty &&
              nomeManual == planoBusca) {
            planData = manual;
            planoManualCarregado = true;
          }
        }
      } catch (e) {
        // Se a tabela manual estiver indisponível por algum motivo,
        // preservamos o funcionamento já existente da tab_planos.
        debugPrint('Erro ao consultar plano manual: $e');
      }

      // ================================================================
      // 2) PLANO NORMAL / COMERCIAL
      // ================================================================
      // Se não houver um plano manual ativo correspondente ao plano do
      // usuário, mantém exatamente a lógica já usada na tab_planos.
      if (!planoManualCarregado) {
        var response = await Supabase.instance.client
            .from('tab_planos')
            .select()
            .or('nome_plano.eq.$planoBusca,nome_plano.eq.${_tipoUsuarioLogado.toLowerCase()}-$planoBusca')
            .limit(1);

        if (response.isEmpty) {
          response = await Supabase.instance.client
              .from('tab_planos')
              .select()
              .ilike('nome_plano', '%$planoBusca%')
              .limit(1);
        }

        if (response.isNotEmpty) {
          planData = Map<String, dynamic>.from(response.first as Map);
        }
      }

      if (planData == null || !mounted) return;

      // ================================================================
      // 3) APLICA OS LIMITES
      // ================================================================
      // Os campos abaixo são compartilhados entre tab_planos e
      // tab_planos_manuais, portanto todo o restante da tela continua
      // usando as mesmas variáveis e as mesmas validações.
      setState(() {
        final qtdFotos = planData!['limite_fotos'] ?? planData!['fotos'];
        if (qtdFotos != null) {
          _limiteFotosPlano = _converterLimitePlano(qtdFotos, 1);
        }

        final qtdVideos = planData!['qtde_videos'] ??
            planData!['limite_videos'] ??
            planData!['videos'];
        if (qtdVideos != null) {
          _limiteVideosPlano = _converterLimitePlano(qtdVideos, 1);
        }

        final qtdPostagem = planData!['qtde_postagem'] ??
            planData!['limite_postagens'] ??
            planData!['limite_postagem'] ??
            planData!['quantidade_postagens'];
        if (qtdPostagem != null) {
          _qtdePostagemPermitida = _converterLimitePlano(qtdPostagem, 1);
        }

        final qtdServicos = planData!['limite_servico'] ??
            planData!['limite_servicos'] ??
            planData!['servicos'];
        if (qtdServicos != null) {
          _limiteServicosPlano = _converterLimitePlano(qtdServicos, 1);
        }

        final fbPermissao = planData!['link_facebook'];
        final igPermissao = planData!['link_instagram'];

        _temPermissaoFacebook = _valorPlanoHabilitado(fbPermissao);
        _temPermissaoInstagram = _valorPlanoHabilitado(igPermissao);
      });

      debugPrint(
        planoManualCarregado
            ? 'Plano manual carregado: $nomePlanoAtivo | '
                'postagens=$_qtdePostagemPermitida, '
                'fotos=$_limiteFotosPlano, '
                'videos=$_limiteVideosPlano, '
                'servicos=$_limiteServicosPlano'
            : 'Plano tab_planos carregado: $nomePlanoAtivo | '
                'postagens=$_qtdePostagemPermitida, '
                'fotos=$_limiteFotosPlano, '
                'videos=$_limiteVideosPlano, '
                'servicos=$_limiteServicosPlano',
      );
    } catch (e) {
      debugPrint('Erro ao carregar plano: $e');
    }
  }

  int _converterLimitePlano(dynamic valor, int valorPadrao) {
    if (valor == null) return valorPadrao;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString().trim()) ?? valorPadrao;
  }

  bool _valorPlanoHabilitado(dynamic valor) {
    if (valor == null) return false;
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;

    final texto = valor.toString().trim().toLowerCase();
    return texto == 'sim' || texto == 'true' || texto == '1' || texto == 'yes';
  }

  Future<void> _carregarMinhasDemandas(String userId) async {
    setState(() => _carregandoDemandas = true);
    try {
      final data = await Supabase.instance.client
          .from('tab_demandas_clientes')
          .select()
          .eq('cliente_id', userId)
          .order('id', ascending: false);

      setState(() {
        _minhasDemandas = List<Map<String, dynamic>>.from(data);
        _carregandoDemandas = false;
      });
    } catch (e) {
      setState(() => _carregandoDemandas = false);
    }
  }

  Future<void> _adicionarFotoTrabalho() async {
    if (_fotosTrabalhosUrls.length >= _limiteFotosPlano) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text("Seu plano permite no máximo $_limiteFotosPlano foto(s)!"),
            backgroundColor: Colors.amber[800]),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _enviandoFotoTrabalho = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final file = File(pickedFile.path);
      final fileName =
          'trabalhos/${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      const bucketName = 'fotos_perfil';

      await Supabase.instance.client.storage
          .from(bucketName)
          .upload(fileName, file);
      final publicUrl = Supabase.instance.client.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      setState(() {
        _fotosTrabalhosUrls.add(publicUrl);
        _enviandoFotoTrabalho = false;
      });

      if (_idDemandaEmEdicao != null) {
        await Supabase.instance.client
            .from('tab_demandas_clientes')
            .update({'fotos_trabalhos': _fotosTrabalhosUrls}).eq(
                'id', _idDemandaEmEdicao!);
      }
    } catch (e) {
      setState(() => _enviandoFotoTrabalho = false);
      debugPrint('Erro ao adicionar foto de trabalho: $e');
    }
  }

  Future<void> _removerFotoTrabalho(String url) async {
    try {
      setState(() => _fotosTrabalhosUrls.remove(url));

      if (_idDemandaEmEdicao != null) {
        await Supabase.instance.client
            .from('tab_demandas_clientes')
            .update({'fotos_trabalhos': _fotosTrabalhosUrls}).eq(
                'id', _idDemandaEmEdicao!);
      }
    } catch (e) {
      debugPrint('Erro ao remover foto: $e');
    }
  }

  Future<void> _adicionarVideoTrabalho() async {
    if (_videosTrabalhosUrls.length >= _limiteVideosPlano) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "Seu plano permite no máximo $_limiteVideosPlano vídeo(s)!"),
            backgroundColor: Colors.amber[800]),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (pickedFile == null) return;

    final file = File(pickedFile.path);

    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();

      if (duration.inSeconds > 30) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("O vídeo não pode ter mais de 30 segundos!"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Erro ao verificar duração do vídeo: $e');
    }

    setState(() => _enviandoVideoTrabalho = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final fileName =
          'videos/${user.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      const bucketName = 'fotos_perfil';

      await Supabase.instance.client.storage
          .from(bucketName)
          .upload(fileName, file);
      final publicUrl = Supabase.instance.client.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      setState(() {
        _videosTrabalhosUrls.add(publicUrl);
        _enviandoVideoTrabalho = false;
      });

      if (_idDemandaEmEdicao != null) {
        await Supabase.instance.client
            .from('tab_demandas_clientes')
            .update({'videos_trabalhos': _videosTrabalhosUrls}).eq(
                'id', _idDemandaEmEdicao!);
      }
    } catch (e) {
      setState(() => _enviandoVideoTrabalho = false);
      debugPrint('Erro ao adicionar vídeo de trabalho: $e');
    }
  }

  Future<void> _removerVideoTrabalho(String url) async {
    try {
      setState(() => _videosTrabalhosUrls.remove(url));

      if (_idDemandaEmEdicao != null) {
        await Supabase.instance.client
            .from('tab_demandas_clientes')
            .update({'videos_trabalhos': _videosTrabalhosUrls}).eq(
                'id', _idDemandaEmEdicao!);
      }
    } catch (e) {
      debugPrint('Erro ao remover vídeo: $e');
    }
  }

  void _redirecionarLogin() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AcheObraHome()),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _selecionarEEnviarFoto() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() {
      _novaImagemArquivo = File(pickedFile.path);
      _enviandoFoto = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final fileName =
          '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      const bucketName = 'fotos_perfil';

      await Supabase.instance.client.storage
          .from(bucketName)
          .upload(fileName, _novaImagemArquivo!);
      final publicUrl = Supabase.instance.client.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      await Supabase.instance.client
          .from('tab_usuarios')
          .update({'foto_url': publicUrl}).eq('id', user.id);

      setState(() {
        _fotoUrl = publicUrl;
        _enviandoFoto = false;
      });
    } catch (e) {
      setState(() => _enviandoFoto = false);
    }
  }

  Future<void> _buscarCidades(String estado,
      {bool manterCidadeAtual = false}) async {
    setState(() {
      _carregandoCidades = true;
      if (!manterCidadeAtual) {
        _cidadeSelecionada = null;
        _listaCidades = [];
      }
    });
    try {
      final data = await Supabase.instance.client
          .from('tab_localidades')
          .select('municipio')
          .eq('estado', estado)
          .order('municipio', ascending: true);

      setState(() {
        _listaCidades =
            (data as List).map((e) => e['municipio'].toString()).toList();
        if (manterCidadeAtual &&
            _cidadeSelecionada != null &&
            !_listaCidades.contains(_cidadeSelecionada)) {
          _cidadeSelecionada = null;
        }
        _carregandoCidades = false;
      });
    } catch (e) {
      setState(() => _carregandoCidades = false);
    }
  }

  Future<void> _buscarCidadesServico(String estado,
      {bool manterCidadeAtual = false}) async {
    setState(() {
      _carregandoCidadesServico = true;
      if (!manterCidadeAtual) {
        _cidadeServico = null;
        _listaCidadesServico = [];
      }
    });
    try {
      final data = await Supabase.instance.client
          .from('tab_localidades')
          .select('municipio')
          .eq('estado', estado)
          .order('municipio', ascending: true);

      setState(() {
        _listaCidadesServico =
            (data as List).map((e) => e['municipio'].toString()).toList();
        if (manterCidadeAtual &&
            _cidadeServico != null &&
            !_listaCidadesServico.contains(_cidadeServico)) {
          _cidadeServico = null;
        }
        _carregandoCidadesServico = false;
      });
    } catch (e) {
      setState(() => _carregandoCidadesServico = false);
    }
  }

  Future<void> _carregarProfissoesDoBanco() async {
    try {
      final data = await Supabase.instance.client
          .from('tab_profissoes')
          .select('id, profissao_nome')
          .order('profissao_nome', ascending: true);
      setState(() {
        _listaProfissoesBanco = data as List;
        for (var item in _listaProfissoesBanco) {
          _servicosSelecionados[item['profissao_nome']] = false;
        }
        _isLoadingProfissoes = false;
      });
    } catch (e) {
      setState(() => _isLoadingProfissoes = false);
    }
  }

  void _abrirModalEsqueciSenha() {
    final emailRecuperacaoController =
        TextEditingController(text: _emailController.text);
    showDialog(
      context: context,
      builder: (context) {
        bool enviando = false;
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1a2c42),
              title: const Text("Recuperar Senha",
                  style: TextStyle(
                      color: Color(0xFFff9800), fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Digite seu e-mail cadastrado para receber o link de redefinição:",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: emailRecuperacaoController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "E-MAIL",
                      labelStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar",
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFff9800)),
                  onPressed: enviando
                      ? null
                      : () async {
                          final email = emailRecuperacaoController.text.trim();
                          if (email.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Informe o e-mail!"),
                                  backgroundColor: Colors.redAccent),
                            );
                            return;
                          }
                          setStateModal(() => enviando = true);
                          try {
                            await Supabase.instance.client.auth
                                .resetPasswordForEmail(email);
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        "E-mail de recuperação enviado com sucesso!"),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            setStateModal(() => enviando = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text("Erro ao enviar: $e"),
                                    backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        },
                  child: enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text("ENVIAR",
                          style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _salvarDados() async {
    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Insira um e-mail válido."),
              backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    final senhaAntiga = _senhaAntigaController.text;
    final novaSenha = _novaSenhaController.text;
    final confirmarSenha = _confirmarSenhaController.text;

    if (senhaAntiga.isNotEmpty ||
        novaSenha.isNotEmpty ||
        confirmarSenha.isNotEmpty) {
      if (senhaAntiga.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Informe a senha antiga para prosseguir com a alteração."),
                backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
      if (novaSenha.length < 6) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("A nova senha deve ter pelo menos 6 caracteres."),
                backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
      if (novaSenha != confirmarSenha) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("As novas senhas não coincidem."),
                backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: senhaAntiga,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("A senha antiga está incorreta."),
                backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final novoNome = _nomeController.text.toUpperCase();
      Map<String, dynamic> updateData = {
        'usuario_nome': novoNome,
        'email': email,
        'whatsapp': _whatsappController.text,
        'estado': _estadoSelecionado,
        'cidade': _cidadeSelecionada,
        'link_facebook': _facebookController.text.trim(),
        'link_instagram': _instagramController.text.trim(),
      };

      try {
        await Supabase.instance.client
            .from('tab_usuarios')
            .update(updateData)
            .eq('id', user.id);

        if (novaSenha.isNotEmpty) {
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(password: novaSenha),
          );
          _senhaAntigaController.clear();
          _novaSenhaController.clear();
          _confirmarSenhaController.clear();
        }
      } catch (_) {
        updateData.remove('tipo');
        await Supabase.instance.client
            .from('tab_usuarios')
            .update(updateData)
            .eq('id', user.id);

        if (novaSenha.isNotEmpty) {
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(password: novaSenha),
          );
          _senhaAntigaController.clear();
          _novaSenhaController.clear();
          _confirmarSenhaController.clear();
        }
      }

      setState(() => _nomeExibicao = novoNome);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Dados salvos com sucesso!")));
      }
    }
  }

  void _abrirFormularioNovaDemanda() {
    if (_minhasDemandas.length >= _qtdePostagemPermitida) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "Limite de $_qtdePostagemPermitida postagem(ns) atingido!"),
            backgroundColor: Colors.amber[800]),
      );
      return;
    }

    setState(() {
      _idDemandaEmEdicao = null;
      _descricaoController.clear();
      _bairroController.clear();
      _fotosTrabalhosUrls = [];
      _videosTrabalhosUrls = [];
      if (_tipoUsuarioLogado == 'cliente') _tipoEscolhido = null;
      _servicosSelecionados.updateAll((key, value) => false);
      _estadoServico = _estadoSelecionado;
      _cidadeServico = _cidadeSelecionada;
      _modoTelaAba1 = 'formulario';
    });

    if (_estadoServico != null) {
      _buscarCidadesServico(_estadoServico!, manterCidadeAtual: true);
    }
  }

  void _abrirFormularioEdicaoDemanda(Map<String, dynamic> demanda) {
    setState(() {
      _idDemandaEmEdicao = demanda['id'].toString();
      _descricaoController.text = demanda['descricao_detalhada'] ?? '';
      _bairroController.text = demanda['bairro'] ?? '';
      _tipoEscolhido = demanda['tipo_profissional'] ?? 'Profissional';
      _estadoServico = demanda['estado'] ?? _estadoSelecionado;
      _cidadeServico = demanda['cidade'] ?? _cidadeSelecionada;

      final fotosSalvas = demanda['fotos_trabalhos'];
      if (fotosSalvas != null && fotosSalvas is List) {
        _fotosTrabalhosUrls = fotosSalvas.map((e) => e.toString()).toList();
      } else {
        _fotosTrabalhosUrls = [];
      }

      final videosSalvos = demanda['videos_trabalhos'];
      if (videosSalvos != null && videosSalvos is List) {
        _videosTrabalhosUrls = videosSalvos.map((e) => e.toString()).toList();
      } else {
        _videosTrabalhosUrls = [];
      }

      _servicosSelecionados.updateAll((key, value) => false);
      final servicosSalvos = demanda['servicos_desejados'];
      if (servicosSalvos != null && servicosSalvos is List) {
        for (var s in servicosSalvos) {
          if (_servicosSelecionados.containsKey(s)) {
            _servicosSelecionados[s] = true;
          }
        }
      }
      _modoTelaAba1 = 'formulario';
    });

    if (_estadoServico != null) {
      _buscarCidadesServico(_estadoServico!, manterCidadeAtual: true);
    }
  }

  Future<void> _salvarDemanda() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    List<String> marcados = [];
    if (_tipoEscolhido == 'Profissional') {
      marcados = _servicosSelecionados.entries
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toList();
      if (marcados.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Selecione ao menos um serviço!"),
              backgroundColor: Colors.redAccent),
        );
        return;
      }
    }

    final descricao = _descricaoController.text.trim();
    if (descricao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Insira uma descrição!"),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSalvandoDemanda = true);

    try {
      await Supabase.instance.client.from('tab_usuarios').update({
        'link_facebook': _facebookController.text.trim(),
        'link_instagram': _instagramController.text.trim(),
      }).eq('id', user.id);

      final dadosDemanda = {
        'cliente_id': user.id,
        'tipo_profissional': _tipoEscolhido ?? 'Profissional',
        'servicos_desejados': marcados.isNotEmpty ? marcados : null,
        'descricao_detalhada': descricao,
        'estado': _estadoServico,
        'cidade': _cidadeServico,
        'bairro': _bairroController.text.trim().toUpperCase(),
        'fotos_trabalhos': _fotosTrabalhosUrls,
        'videos_trabalhos': _videosTrabalhosUrls,
      };

      if (_idDemandaEmEdicao != null) {
        await Supabase.instance.client
            .from('tab_demandas_clientes')
            .update(dadosDemanda)
            .eq('id', _idDemandaEmEdicao!);
      } else {
        await Supabase.instance.client
            .from('tab_demandas_clientes')
            .insert(dadosDemanda);
      }

      await _carregarMinhasDemandas(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Salvo com sucesso!"),
            backgroundColor: Colors.green));
        setState(() {
          _modoTelaAba1 = 'lista';
          _idDemandaEmEdicao = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro: $e"), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isSalvandoDemanda = false);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    _senhaAntigaController.dispose();
    _novaSenhaController.dispose();
    _confirmarSenhaController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _bairroController.dispose();
    _descricaoController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildDrawer(BuildContext context, bool isPrestador) {
    return Drawer(
      backgroundColor: const Color(0xFF1a2c42),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF253c59)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFff9800),
                  child: Icon(Icons.person, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 10),
                const Text("Menu Principal",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Text("Ache Obra",
                    style: TextStyle(color: Color(0xFFff9800), fontSize: 14)),
              ],
            ),
          ),
          ListTile(
            leading:
                const Icon(Icons.manage_accounts, color: Color(0xFFff9800)),
            title: const Text("Editar Perfil",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text("Gerencie seus dados e foto",
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            selected: _abaAtiva == 0,
            selectedTileColor: Colors.white12,
            onTap: () {
              setState(() => _abaAtiva = 0);
              Navigator.pop(context);
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.handyman, color: Color(0xFFff9800)),
            title: Text(
                isPrestador ? "Postar Serviço" : "Contratar Profissional",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(
                isPrestador
                    ? "Publique o seu serviço"
                    : "Encontre o que precisa",
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            selected: _abaAtiva == 1,
            selectedTileColor: Colors.white12,
            onTap: () {
              setState(() {
                _abaAtiva = 1;
                _modoTelaAba1 = 'lista';
              });
              Navigator.pop(context);
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.star, color: Color(0xFFff9800)),
            title: const Text("Meus Planos",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text("Gerencie sua assinatura",
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => PlanosUsuarioPage(
                        tipoUsuarioLogado: _tipoUsuarioLogado)),
              );
            },
          ),
          const Divider(color: Colors.white24),
          ExpansionTile(
            leading: const Icon(Icons.miscellaneous_services,
                color: Color(0xFFff9800)),
            title: const Text("Outros Serviços",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            iconColor: const Color(0xFFff9800),
            collapsedIconColor: Colors.white70,
            childrenPadding: const EdgeInsets.only(left: 20),
            children: [
              ListTile(
                leading: const Icon(Icons.request_quote,
                    color: Colors.white70, size: 20),
                title: const Text("Orçamento",
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ListaOrcamentosPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.shopping_cart_checkout,
                    color: Color(0xFFff9800), size: 20),
                title: const Text("Pedido de Materiais",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                selected: _abaAtiva == 2,
                onTap: () {
                  setState(() => _abaAtiva = 2);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.white70),
            title: const Text("Suporte", style: TextStyle(color: Colors.white)),
            subtitle: const Text("acheobra@gmail.com",
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.white70),
            title: const Text("Sair da Conta",
                style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AcheObraHome()),
                  (Route<dynamic> route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAcesso) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a2c42),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFFff9800))),
      );
    }

    bool isPrestador = _tipoUsuarioLogado == 'profissional' ||
        _tipoUsuarioLogado == 'arquiteto' ||
        _tipoUsuarioLogado == 'engenheiro';

    String tituloAppBar = _abaAtiva == 0
        ? "Painel do Cliente"
        : (_abaAtiva == 1
            ? (isPrestador ? "Meus Serviços Publicados" : "Minhas Solicitações")
            : "Pedido de Materiais");

    String textoBotaoSalvar = isPrestador ? "SALVAR SERVIÇO" : "SALVAR DEMANDA";
    int postagensRestantes = (_qtdePostagemPermitida - _minhasDemandas.length);
    if (postagensRestantes < 0) postagensRestantes = 0;

    return Scaffold(
      backgroundColor: const Color(0xFF1a2c42),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () {
            Navigator.pop(
              context,
            );
          },
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFFff9800),
            size: 24,
          ),
        ),
        title: Text(
          tituloAppBar,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1a2c42),
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Color(0xFFff9800),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            if (_abaAtiva == 0) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF253c59),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFff9800), width: 1),
                ),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white12,
                          backgroundImage: _novaImagemArquivo != null
                              ? FileImage(_novaImagemArquivo!) as ImageProvider
                              : (_fotoUrl != null && _fotoUrl!.isNotEmpty
                                  ? NetworkImage(_fotoUrl!) as ImageProvider
                                  : null),
                          child: (_novaImagemArquivo == null &&
                                  (_fotoUrl == null || _fotoUrl!.isEmpty))
                              ? const Icon(Icons.person,
                                  size: 50, color: Colors.white54)
                              : null,
                        ),
                        if (_enviandoFoto)
                          const Positioned.fill(
                              child: CircularProgressIndicator(
                                  color: Color(0xFFff9800))),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap:
                                _enviandoFoto ? null : _selecionarEEnviarFoto,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                  color: Color(0xFFff9800),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(isPrestador ? "CONTA PROFISSIONAL" : "CONTA CLIENTE",
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(
                        _nomeExibicao.isNotEmpty
                            ? _nomeExibicao
                            : "Carregando...",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
              _buildCard("Meus Dados", [
                _buildEditableField("Nome:", _nomeController,
                    textCapitalization: TextCapitalization.characters),
                _buildEditableField("E-mail:", _emailController),
                _buildEditableField("WhatsApp:", _whatsappController),
                _buildEditableField("Senha Antiga:", _senhaAntigaController,
                    obscureText: true),
                _buildEditableField(
                    "Nova Senha (opcional):", _novaSenhaController,
                    obscureText: true),
                _buildEditableField(
                    "Confirmar Nova Senha:", _confirmarSenhaController,
                    obscureText: true),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _abrirModalEsqueciSenha,
                    child: const Text(
                      "Esqueci minha senha",
                      style: TextStyle(
                        color: Color(0xFFff9800),
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                _buildDropdownField(
                  label: "Estado:",
                  value: _estadoSelecionado,
                  items: _listaEstados,
                  onChanged: (val) {
                    setState(() {
                      _estadoSelecionado = val;
                      _cidadeSelecionada = null;
                    });
                    if (val != null) _buscarCidades(val);
                  },
                ),
                _buildDropdownField(
                  label: "Cidade:",
                  value: _cidadeSelecionada,
                  items: _listaCidades,
                  isLoading: _carregandoCidades,
                  onChanged: (_carregandoCidades || _listaCidades.isEmpty)
                      ? null
                      : (val) => setState(() => _cidadeSelecionada = val),
                ),
              ]),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _salvarDados,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFff9800),
                      padding: const EdgeInsets.symmetric(vertical: 15)),
                  child: const Text("SALVAR ALTERAÇÕES",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            if (_abaAtiva == 1) ...[
              if (_modoTelaAba1 == 'lista') ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF253c59),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: const Color(0xFFff9800), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("STATUS DE POSTAGENS",
                                  style: TextStyle(
                                      color: Color(0xFFff9800),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                  "Publicadas: ${_minhasDemandas.length} | Limite: $_qtdePostagemPermitida",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ],
                          ),
                          if (postagensRestantes > 0)
                            ElevatedButton.icon(
                              onPressed: _abrirFormularioNovaDemanda,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFff9800),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8)),
                              icon: const Icon(Icons.add,
                                  color: Colors.white, size: 18),
                              label: const Text("Nova Postagem",
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: Colors.red[700],
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Text("Limite Atingido",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => PlanosUsuarioPage(
                                      tipoUsuarioLogado: _tipoUsuarioLogado)),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFff9800),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.star,
                              color: Colors.white, size: 18),
                          label: const Text(
                            "Destacar Meu Anúncio",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _carregandoDemandas
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(30.0),
                            child: CircularProgressIndicator(
                                color: Color(0xFFff9800))))
                    : _minhasDemandas.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                                color: const Color(0xFF253c59),
                                borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              children: [
                                const Icon(Icons.folder_open,
                                    color: Colors.white54, size: 48),
                                const SizedBox(height: 10),
                                const Text("Você ainda não possui publicações.",
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 14),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 15),
                                ElevatedButton(
                                  onPressed: _abrirFormularioNovaDemanda,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFff9800)),
                                  child: const Text("Criar Primeira Postagem",
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _minhasDemandas.length,
                            itemBuilder: (context, index) {
                              final item = _minhasDemandas[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF253c59),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            item['tipo_profissional'] ??
                                                'Serviço',
                                            style: const TextStyle(
                                                color: Color(0xFFff9800),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15)),
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Color(0xFFff9800),
                                              size: 20),
                                          onPressed: () =>
                                              _abrirFormularioEdicaoDemanda(
                                                  item),
                                          tooltip: "Editar Postagem",
                                        ),
                                      ],
                                    ),
                                    const Divider(color: Colors.white24),
                                    Text(item['descricao_detalhada'] ?? '',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 13),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 8),
                                    Text(
                                        "Local: ${item['cidade'] ?? ''}/${item['estado'] ?? ''} - Bairro: ${item['bairro'] ?? 'Não informado'}",
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                  ],
                                ),
                              );
                            },
                          ),
              ] else ...[
                _buildCard(
                    _idDemandaEmEdicao == null
                        ? "Nova Postagem"
                        : "Editar Postagem",
                    [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              _idDemandaEmEdicao == null
                                  ? "CRIAR PUBLICAÇÃO"
                                  : "EDITAR PUBLICAÇÃO",
                              style: const TextStyle(
                                  color: Color(0xFFff9800),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _modoTelaAba1 = 'lista'),
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white70, size: 16),
                            label: const Text("Voltar à Lista",
                                style: TextStyle(color: Colors.white70)),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24),
                      if (!isPrestador) ...[
                        const Text("O QUE VOCÊ DESEJA CONTRATAR?",
                            style: TextStyle(
                                color: Color(0xFFff9800),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        RadioListTile<String>(
                            title: const Text(
                                "Profissional (Mão de Obra / Execução)",
                                style: TextStyle(color: Colors.white)),
                            value: 'Profissional',
                            groupValue: _tipoEscolhido,
                            activeColor: const Color(0xFFff9800),
                            onChanged: (val) =>
                                setState(() => _tipoEscolhido = val)),
                        RadioListTile<String>(
                            title: const Text("Arquiteto (Projetos e Design)",
                                style: TextStyle(color: Colors.white)),
                            value: 'Arquiteto',
                            groupValue: _tipoEscolhido,
                            activeColor: const Color(0xFFff9800),
                            onChanged: (val) =>
                                setState(() => _tipoEscolhido = val)),
                        RadioListTile<String>(
                            title: const Text(
                                "Engenheiro (Projetos e Cálculo Estrutural)",
                                style: TextStyle(color: Colors.white)),
                            value: 'Engenheiro',
                            groupValue: _tipoEscolhido,
                            activeColor: const Color(0xFFff9800),
                            onChanged: (val) =>
                                setState(() => _tipoEscolhido = val)),
                      ],
                      if (_tipoEscolhido == 'Profissional') ...[
                        const SizedBox(height: 10),
                        Text(
                            "SELECIONE OS SERVIÇOS (MÁX: $_limiteServicosPlano):",
                            style: const TextStyle(
                                color: Color(0xFFff9800),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 5),
                        _isLoadingProfissoes
                            ? const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: CircularProgressIndicator(
                                        color: Color(0xFFff9800))))
                            : Container(
                                height: 200,
                                decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.white24)),
                                child: Scrollbar(
                                  controller: _scrollController,
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    itemCount: _listaProfissoesBanco.length,
                                    itemBuilder: (context, index) {
                                      String nomeProfissao =
                                          _listaProfissoesBanco[index]
                                              ['profissao_nome'];
                                      return CheckboxListTile(
                                        title: Text(nomeProfissao,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14)),
                                        value: _servicosSelecionados[
                                                nomeProfissao] ??
                                            false,
                                        onChanged: (val) {
                                          if (val == true) {
                                            int selecionadosAtuais =
                                                _servicosSelecionados.values
                                                    .where((e) => e == true)
                                                    .length;
                                            if (selecionadosAtuais >=
                                                _limiteServicosPlano) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        "Seu plano permite selecionar no máximo $_limiteServicosPlano serviço(s)!"),
                                                    backgroundColor:
                                                        Colors.amber[800]),
                                              );
                                              return;
                                            }
                                          }
                                          setState(() => _servicosSelecionados[
                                              nomeProfissao] = val ?? false);
                                        },
                                        activeColor: const Color(0xFFff9800),
                                        checkColor: Colors.white,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8),
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ],
                      if (isPrestador) ...[
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("MEUS TRABALHOS",
                                style: TextStyle(
                                    color: Color(0xFFff9800),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            Text(
                                "${_fotosTrabalhosUrls.length} de $_limiteFotosPlano foto(s)",
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10),
                          itemCount: _fotosTrabalhosUrls.length +
                              (_fotosTrabalhosUrls.length < _limiteFotosPlano
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index == _fotosTrabalhosUrls.length) {
                              return InkWell(
                                onTap: _enviandoFotoTrabalho
                                    ? null
                                    : _adicionarFotoTrabalho,
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFFff9800),
                                          width: 1)),
                                  child: _enviandoFotoTrabalho
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                              color: Color(0xFFff9800)))
                                      : const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.add_a_photo,
                                                color: Color(0xFFff9800),
                                                size: 28),
                                            SizedBox(height: 4),
                                            Text("Adicionar",
                                                style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11)),
                                          ],
                                        ),
                                ),
                              );
                            }
                            final url = _fotosTrabalhosUrls[index];
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child:
                                        Image.network(url, fit: BoxFit.cover)),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () => _removerFotoTrabalho(url),
                                    child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            size: 16, color: Colors.white)),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("VÍDEOS DOS TRABALHOS",
                                style: TextStyle(
                                    color: Color(0xFFff9800),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            Text(
                                "${_videosTrabalhosUrls.length} de $_limiteVideosPlano vídeo(s)",
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                        const Divider(color: Colors.white24),
                        const Padding(
                          padding: EdgeInsets.only(top: 2, bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 15, color: Colors.white60),
                              SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  "Duração máxima: 30 segundos por vídeo",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10),
                          itemCount: _videosTrabalhosUrls.length +
                              (_videosTrabalhosUrls.length < _limiteVideosPlano
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index == _videosTrabalhosUrls.length) {
                              return InkWell(
                                onTap: _enviandoVideoTrabalho
                                    ? null
                                    : _adicionarVideoTrabalho,
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFFff9800),
                                          width: 1)),
                                  child: _enviandoVideoTrabalho
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                              color: Color(0xFFff9800)))
                                      : const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.videocam,
                                                color: Color(0xFFff9800),
                                                size: 28),
                                            SizedBox(height: 4),
                                            Text("Adicionar Vídeo",
                                                style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11)),
                                          ],
                                        ),
                                ),
                              );
                            }
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const Center(
                                    child: Icon(Icons.play_circle_fill,
                                        color: Colors.white, size: 40),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () => _removerVideoTrabalho(
                                          _videosTrabalhosUrls[index]),
                                      child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle),
                                          child: const Icon(Icons.close,
                                              size: 16, color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text("LOCAL DO SERVIÇO",
                          style: TextStyle(
                              color: Color(0xFFff9800),
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 10),
                      _buildDropdownField(
                        label: "Estado:",
                        value: _estadoServico,
                        items: _listaEstados,
                        onChanged: (val) {
                          setState(() {
                            _estadoServico = val;
                            _cidadeServico = null;
                          });
                          if (val != null) _buscarCidadesServico(val);
                        },
                      ),
                      _buildDropdownField(
                        label: "Cidade:",
                        value: _cidadeServico,
                        items: _listaCidadesServico,
                        isLoading: _carregandoCidadesServico,
                        onChanged: (_carregandoCidadesServico ||
                                _listaCidadesServico.isEmpty)
                            ? null
                            : (val) => setState(() => _cidadeServico = val),
                      ),
                      _buildEditableField("Bairro:", _bairroController,
                          textCapitalization: TextCapitalization.characters),
                      const SizedBox(height: 20),
                      const Text("DESCRIÇÃO DO TRABALHO:",
                          style: TextStyle(
                              color: Color(0xFFff9800),
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _descricaoController,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText:
                              "Descreva com detalhes o que precisa ser feito...",
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white12,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                      if (isPrestador &&
                          (_temPermissaoFacebook ||
                              _temPermissaoInstagram)) ...[
                        const SizedBox(height: 20),
                        const Text("REDES SOCIAIS",
                            style: TextStyle(
                                color: Color(0xFFff9800),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                            "Insira o link completo para os clientes encontrarem seu perfil.",
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                        const Divider(color: Colors.white24),
                        if (_temPermissaoFacebook)
                          _buildEditableField(
                              "Link do Facebook:", _facebookController),
                        if (_temPermissaoInstagram)
                          _buildEditableField(
                              "Link do Instagram:", _instagramController),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              (_tipoEscolhido == null || _isSalvandoDemanda)
                                  ? null
                                  : _salvarDemanda,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFff9800),
                              disabledBackgroundColor: Colors.white24,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 15)),
                          child: _isSalvandoDemanda
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(textoBotaoSalvar,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
              ],
            ],
            if (_abaAtiva == 2) ...[
              const PedidoMateriaisPage(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFFff9800),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller,
      {TextCapitalization textCapitalization = TextCapitalization.none,
      bool obscureText = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            textCapitalization: textCapitalization,
            obscureText: obscureText,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 12, horizontal: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(
      {required String label,
      required String? value,
      required List<String> items,
      required void Function(String?)? onChanged,
      bool isLoading = false}) {
    final validValue = items.contains(value) ? value : null;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 5),
            DropdownButtonFormField<String>(
              value: validValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF253c59),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 12, horizontal: 10)),
              hint: isLoading
                  ? const Text("Carregando...",
                      style: TextStyle(color: Colors.white54))
                  : const Text("Selecione",
                      style: TextStyle(color: Colors.white54)),
              items: items
                  .map((String item) =>
                      DropdownMenuItem<String>(value: item, child: Text(item)))
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ));
  }
}
