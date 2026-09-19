//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2011-07-10 GONG Chen <chen.sst@gmail.com>
//
#ifndef RIME_TABLE_TRANSLATOR_H_
#define RIME_TABLE_TRANSLATOR_H_

#include <rime/common.h>
#include <rime/config.h>
#include <rime/translation.h>
#include <rime/translator.h>
#include <rime/algo/algebra.h>
#include <rime/dict/dictionary.h>
#include <rime/dict/user_dictionary.h>
#include <rime/gear/memory.h>
#include <rime/gear/translator_commons.h>

namespace rime {

class Poet;
class UnityTableEncoder;

class TableTranslator : public Translator,
                        public Memory,
                        public TranslatorOptions {
 public:
  TableTranslator(const Ticket& ticket);

  virtual an<Translation> Query(const string& input, const Segment& segment);
  virtual bool Memorize(const CommitEntry& commit_entry);
  // FR-4b: 将最近一次上屏词条立即加重置顶（Ctrl+=）
  bool PromoteLastCommittedEntry();

  an<Translation> MakeSentence(const string& input,
                               size_t start,
                               bool include_prefix_phrases = false);
  string GetPrecedingText(size_t start) const;
  UnityTableEncoder* encoder() const { return encoder_.get(); }

 protected:
  bool enable_charset_filter_ = false;
  bool enable_encoder_ = false;
  bool enable_sentence_ = true;
  bool sentence_over_completion_ = false;
  bool encode_commit_history_ = true;
  int max_phrase_length_ = 5;
  int max_homographs_ = 1;
  the<Poet> poet_;
  the<UnityTableEncoder> encoder_;

 private:
  // FR-4a (Shurufa): 同一词组连续上屏达到阈值后，对词条加重置顶（持久化进 userdb）
  static constexpr int kShurufaPromoteThreshold = 3;
  static constexpr int kShurufaPromoteCommits = 50;
  string last_shurufa_commit_text_;
  int shurufa_commit_streak_ = 0;
  bool shurufa_boosted_this_streak_ = false;
  void ShurufaPromoteIfNeeded(const CommitEntry& commit_entry);
  vector<DictEntry> last_shurufa_committed_;
};

class TableTranslation : public Translation {
 public:
  TableTranslation(TranslatorOptions* options,
                   const Language* language,
                   const string& input,
                   size_t start,
                   size_t end,
                   const string& preedit,
                   DictEntryIterator&& iter = {},
                   UserDictEntryIterator&& uter = {});

  virtual bool Next();
  virtual an<Candidate> Peek();

 protected:
  virtual bool FetchMoreUserPhrases() { return false; }
  virtual bool FetchMoreTableEntries() { return false; }

  bool CheckEmpty();
  bool PreferUserPhrase();

  an<DictEntry> PreferredEntry(bool prefer_user_phrase) {
    return prefer_user_phrase ? uter_.Peek() : iter_.Peek();
  }

  TranslatorOptions* options_;
  const Language* language_;
  string input_;
  size_t start_;
  size_t end_;
  string preedit_;
  DictEntryIterator iter_;
  UserDictEntryIterator uter_;
};

}  // namespace rime

#endif  // RIME_TABLE_TRANSLATOR_H_
