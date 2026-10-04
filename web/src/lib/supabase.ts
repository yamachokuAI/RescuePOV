import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://dmnaowybbmacwadfiofu.supabase.co';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_pJsAhOpYaWHWfGcwChGAcw_-b3JhO7C';

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
