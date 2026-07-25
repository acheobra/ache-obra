import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import 'pages/feed_page.dart';

class CadastroProfissionalPage extends StatefulWidget {
  const CadastroProfissionalPage({super.key});

  @override
  State<CadastroProfissionalPage> createState() =>
      _CadastroProfissionalPageState();
}

class _CadastroProfissionalPageState extends State<CadastroProfissionalPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _nascimentoController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  final _maskNascimento = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  final _maskSenha = MaskTextInputFormatter(
    mask: '########',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

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
  List<String> _listaCidades = [];
  bool _carregandoCidades = false;
  bool _isLoading = false;
  bool _aceitouTermos = false;
  bool _permanecerConectado = true;

  bool _fazTudo = false;
  bool _impermeabilizador = false;
  bool _encanador = false;
  bool _eletricista = false;
  bool _pintorIndustrial = false;
  bool _telhadista = false;
  bool _carpinteiro = false;
  bool _jardineiro = false;
  bool _vidraceiro = false;
  bool _serralheiro = false;
  bool _azulejista = false;
  bool _instaladorAr = false;
  bool _gesseiro = false;
  bool _pedreiro = false;
  bool _pintor = false;
  bool _mestreObras = false;

  final Color _bgColor = const Color(0xFF1A2C42);
  final Color _primaryColor = const Color(0xFFFF8C00);

  Future<void> _buscarCidades(String estado) async {
    setState(() {
      _carregandoCidades = true;
      _listaCidades = [];
      _cidadeSelecionada = null;
    });

    try {
      final data = await Supabase.instance.client
          .from('tab_localidades')
          .select('municipio')
          .eq('estado', estado)
          .order('municipio', ascending: true);

      setState(() {
        _listaCidades =
            (data as List).map((e) => e['municipio'] as String).toList();
        _carregandoCidades = false;
      });
    } catch (e) {
      setState(() => _carregandoCidades = false);
      debugPrint('Erro ao buscar cidades: $e');
    }
  }

  Future<void> _selecionarDataNascimento() async {
    DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: _primaryColor,
            colorScheme: ColorScheme.light(primary: _primaryColor),
            buttonTheme:
                const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (dataEscolhida != null) {
      String dia = dataEscolhida.day.toString().padLeft(2, '0');
      String mes = dataEscolhida.month.toString().padLeft(2, '0');
      String ano = dataEscolhida.year.toString();

      setState(() {
        _nascimentoController.text = '$dia/$mes/$ano';
      });
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _nascimentoController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _realizarCadastro() async {
    if (!_aceitouTermos ||
        _estadoSelecionado == null ||
        _cidadeSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Preencha todos os campos obrigatórios e aceite os termos!'),
          backgroundColor: Colors.orange));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final senhaTexto = _senhaController.text.trim();
    final regexApenasNumeros = RegExp(r'^[0-9]+$');
    if (!regexApenasNumeros.hasMatch(senhaTexto) ||
        senhaTexto.length < 4 ||
        senhaTexto.length > 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'A senha deve conter apenas números e ter entre 4 e 8 caracteres!'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);

    String? userIdCriado;

    try {
      final supabase = Supabase.instance.client;
      final nomeMaiusculo = _nomeController.text.trim().toUpperCase();

      final AuthResponse response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: senhaTexto,
        data: {'nome': nomeMaiusculo},
      );

      if (response.user != null) {
        userIdCriado = response.user!.id;

        try {
          String dataNascimentoFormatada = '';
          if (_nascimentoController.text.trim().length == 10) {
            List<String> partes = _nascimentoController.text.trim().split('/');
            if (partes.length == 3) {
              dataNascimentoFormatada =
                  '${partes[2]}-${partes[1]}-${partes[0]}';
            }
          }

          String whatsappLimpo =
              _whatsappController.text.replaceAll(RegExp(r'[^0-9]'), '');

          await supabase.from('tab_usuarios').insert({
            'id': userIdCriado,
            'usuario_nome': nomeMaiusculo,
            'dt_nascimento': dataNascimentoFormatada.isNotEmpty
                ? dataNascimentoFormatada
                : null,
            'whatsapp': whatsappLimpo,
            'email': _emailController.text.trim(),
            'estado': _estadoSelecionado,
            'cidade': _cidadeSelecionada,
            'usuario_status': 'aguardando',
            'usuario_tipo': 'profissional',
            'dt_cadastro': DateTime.now().toIso8601String(),
          });

          final Map<String, bool> mapaProfissoes = {
            'Faz Tudo': _fazTudo,
            'Impermeabilizador': _impermeabilizador,
            'Encanador (Hidráulico)': _encanador,
            'Eletricista': _eletricista,
            'Pintor Industrial': _pintorIndustrial,
            'Telhadista': _telhadista,
            'Carpinteiro': _carpinteiro,
            'Jardineiro': _jardineiro,
            'Vidraceiro': _vidraceiro,
            'Serralheiro': _serralheiro,
            'Azulejista': _azulejista,
            'Instalador de Ar Condicionado': _instaladorAr,
            'Gesseiro': _gesseiro,
            'Pedreiro': _pedreiro,
            'Pintor': _pintor,
            'Mestre de Obras': _mestreObras,
          };

          final List<dynamic> catalogoProfissoes = await supabase
              .from('tab_profissoes')
              .select('id, profissao_nome');

          for (var entry in mapaProfissoes.entries) {
            String nomeProfissao = entry.key;
            bool selecionada = entry.value;

            if (selecionada) {
              final match = catalogoProfissoes.firstWhere(
                (p) =>
                    p['profissao_nome'].toString().trim().toLowerCase() ==
                    nomeProfissao.toLowerCase(),
                orElse: () => <String, dynamic>{},
              );

              if (match.isNotEmpty) {
                String profissaoId = match['id'];

                await supabase.from('tab_usuarios_profissoes').insert({
                  'usuario_id': userIdCriado,
                  'profissao_id': profissaoId,
                });
              }
            }
          }
        } catch (dbError) {
          debugPrint('Falha ao salvar nas tabelas: $dbError');
          rethrow;
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FeedPage()),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        String mensagemErro = 'Erro: $error';

        if (error.toString().contains('user_already_exists') ||
            error.toString().contains('User already registered')) {
          mensagemErro = 'E-mail já cadastrado, tente outro!';
        }

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(mensagemErro), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _primaryColor),
        title: const Text(
          'CADASTRO DE PROFISSIONAL',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Icon(Icons.badge_outlined,
                      size: 64, color: _primaryColor),
                ),
                const SizedBox(height: 20),
                _buildTextFormField(
                  controller: _nomeController,
                  label: 'NOME COMPLETO / EMPRESA',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe seu nome ou o nome da empresa';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nascimentoController,
                  inputFormatters: [_maskNascimento],
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'DATA DE NASCIMENTO (DD/MM/AAAA)',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon:
                        Icon(Icons.calendar_today, color: _primaryColor),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.date_range, color: _primaryColor),
                      onPressed: _selecionarDataNascimento,
                      tooltip: 'Abrir Calendário',
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                      labelText: 'ESTADO',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.map, color: _primaryColor)),
                  items: _listaEstados
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _estadoSelecionado = value);
                      _buscarCidades(value);
                    }
                  },
                  validator: (value) =>
                      value == null ? 'Selecione um estado' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                      labelText: 'CIDADE',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon:
                          Icon(Icons.location_city, color: _primaryColor)),
                  value: _cidadeSelecionada,
                  items: _listaCidades
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: _carregandoCidades
                      ? null
                      : (value) => setState(() => _cidadeSelecionada = value),
                  validator: (value) =>
                      value == null ? 'Selecione uma cidade' : null,
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                  controller: _whatsappController,
                  label: 'WHATSAPP',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o número do WhatsApp';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                  controller: _emailController,
                  label: 'E-MAIL',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o e-mail';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Informe um e-mail válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _senhaController,
                  inputFormatters: [_maskSenha],
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  style: const TextStyle(color: Colors.black),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe a senha';
                    }
                    if (value.length < 4 || value.length > 8) {
                      return 'A senha deve ter entre 4 e 8 caracteres';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'SENHA (APENAS NÚMEROS, 4 A 8 DÍGITOS)',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.lock_outline, color: _primaryColor),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SELECIONE SUAS ATUAÇÕES:',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildCheckboxTile('Faz Tudo', _fazTudo,
                    (val) => setState(() => _fazTudo = val)),
                _buildCheckboxTile('Impermeabilizador', _impermeabilizador,
                    (val) => setState(() => _impermeabilizador = val)),
                _buildCheckboxTile('Encanador (Hidráulico)', _encanador,
                    (val) => setState(() => _encanador = val)),
                _buildCheckboxTile('Eletricista', _eletricista,
                    (val) => setState(() => _eletricista = val)),
                _buildCheckboxTile('Pintor Industrial', _pintorIndustrial,
                    (val) => setState(() => _pintorIndustrial = val)),
                _buildCheckboxTile('Telhadista', _telhadista,
                    (val) => setState(() => _telhadista = val)),
                _buildCheckboxTile('Carpinteiro', _carpinteiro,
                    (val) => setState(() => _carpinteiro = val)),
                _buildCheckboxTile('Jardineiro', _jardineiro,
                    (val) => setState(() => _jardineiro = val)),
                _buildCheckboxTile('Vidraceiro', _vidraceiro,
                    (val) => setState(() => _vidraceiro = val)),
                _buildCheckboxTile('Serralheiro', _serralheiro,
                    (val) => setState(() => _serralheiro = val)),
                _buildCheckboxTile('Azulejista', _azulejista,
                    (val) => setState(() => _azulejista = val)),
                _buildCheckboxTile(
                    'Instalador de Ar Condicionado',
                    _instaladorAr,
                    (val) => setState(() => _instaladorAr = val)),
                _buildCheckboxTile('Gesseiro', _gesseiro,
                    (val) => setState(() => _gesseiro = val)),
                _buildCheckboxTile('Pedreiro', _pedreiro,
                    (val) => setState(() => _pedreiro = val)),
                _buildCheckboxTile(
                    'Pintor', _pintor, (val) => setState(() => _pintor = val)),
                _buildCheckboxTile('Mestre de Obras', _mestreObras,
                    (val) => setState(() => _mestreObras = val)),
                const SizedBox(height: 20),
                CheckboxListTile(
                    title: const Text('Permanecer conectado',
                        style: TextStyle(color: Colors.white)),
                    value: _permanecerConectado,
                    onChanged: (val) =>
                        setState(() => _permanecerConectado = val!),
                    activeColor: _primaryColor),
                CheckboxListTile(
                    title: const Text('Li e aceito os termos',
                        style: TextStyle(color: Colors.white)),
                    value: _aceitouTermos,
                    onChanged: (val) => setState(() => _aceitouTermos = val!),
                    activeColor: _primaryColor),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _realizarCadastro,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('CRIAR CONTA PROFISSIONAL',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxTile(
      String title, bool value, Function(bool) onChanged) {
    return CheckboxListTile(
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      value: value,
      onChanged: (val) => onChanged(val ?? false),
      activeColor: _primaryColor,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: _primaryColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
  }
}
