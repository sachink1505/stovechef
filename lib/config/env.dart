class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const dailyRecipeLimit = int.fromEnvironment('DAILY_RECIPE_LIMIT', defaultValue: 5);

  /// Which LLM provider to use: 'gemini' or 'openai'.
  static const llmProvider = String.fromEnvironment('LLM_PROVIDER', defaultValue: 'gemini');
  static const openaiApiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const openaiModel = String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-4o-mini');
}
