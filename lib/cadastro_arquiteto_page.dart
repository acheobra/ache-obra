import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import 'pages/feed_page.dart';

class CadastroArquitetoPage extends StatefulWidget {
  const CadastroArquitetoPage({super.key});

  @override
  State<CadastroArquitetoPage> createState() => _CadastroArquitetoPageState();
}

class _CadastroArquitetoPageState extends State<CadastroArquitetoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _nascimentoController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _especializacaoController = TextEditingController();

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
  bool _senhaOculta = true; // Controla a visibilidade da senha

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
    _especializacaoController.dispose();
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
            'especializacao': _especializacaoController.text.trim(),
            'usuario_status': 'aguardando',
            'usuario_tipo': 'arquiteto',
            'dt_cadastro': DateTime.now().toIso8601String(),
          });
        } catch (dbError) {
          debugPrint('Falha ao salvar no banco: $dbError');
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
          'CADASTRO DE ARQUITETO(A)',
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
                  child:
                      Icon(Icons.architecture, size: 64, color: _primaryColor),
                ),
                const SizedBox(height: 24),
                _buildTextFormField(
                  controller: _nomeController,
                  label: 'NOME COMPLETO / EMPRESA',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe seu nome ou empresa';
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
                      return 'Informe o WhatsApp';
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
                  obscureText: _senhaOculta, // Controlado pelo estado do ícone
                  style: const TextStyle(color: Colors.black),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe a senha';
                    }
                    if (value.length < 4 || value.length > 8) {
                      return 'A senha deve ter entre 4 e 8 dígitos';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'SENHA (APENAS NÚMEROS, 4 A 8 DÍGITOS)',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.lock_outline, color: _primaryColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaOculta ? Icons.visibility_off : Icons.visibility,
                        color: _primaryColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _senhaOculta =
                              !_senhaOculta; // Alterna a visualização da senha
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _especializacaoController,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Informe suas especialidades',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 64),
                      child: Icon(Icons.edit_note, color: _primaryColor),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
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
                          : const Text('CRIAR CONTA DE ARQUITETO(A)',
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
