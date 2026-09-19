//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2013-11-05 GONG Chen <chen.sst@gmail.com>
//
#include <rime/candidate.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/schema.h>
#include <rime/segmentation.h>
#include <rime/translation.h>
#include <rime/dict/reverse_lookup_dictionary.h>
#include <rime/gear/reverse_lookup_filter.h>
#include <rime/gear/translator_commons.h>

namespace rime {

class ReverseLookupFilterTranslation : public CacheTranslation {
 public:
  ReverseLookupFilterTranslation(an<Translation> translation,
                                 ReverseLookupFilter* filter)
      : CacheTranslation(translation), filter_(filter) {}
  virtual an<Candidate> Peek();

 protected:
  ReverseLookupFilter* filter_;
};

an<Candidate> ReverseLookupFilterTranslation::Peek() {
  auto cand = CacheTranslation::Peek();
  if (cand) {
    filter_->Process(cand);
  }
  return cand;
}

ReverseLookupFilter::ReverseLookupFilter(const Ticket& ticket)
    : Filter(ticket), TagMatching(ticket) {
  if (ticket.name_space == "filter") {
    name_space_ = "reverse_lookup";
  }
  // 门控配置必须在这里读，不能懒到 Initialize()：
  // 建菜单时先调 AppliesToSegment（要 show_if），取到候选后才调 Apply→Initialize。
  // 放 Initialize 里，首个输入的第一次构菜单永远看到空值，空值按「不过滤」处理，
  // 单字输入（首构即终构）就会漏码，且段状态 kGuess 之后不再重翻，漏上的码一直挂着。
  // TagMatching 的 tags 就是这么在构造时读的，同等待遇。
  if (ticket.schema) {
    if (Config* config = ticket.schema->config()) {
      config->GetBool(name_space_ + "/overwrite_comment", &overwrite_comment_);
      config->GetBool(name_space_ + "/append_comment", &append_comment_);
      config->GetString(name_space_ + "/show_if_input_contains",
                        &show_if_input_contains_);
      comment_formatter_.Load(config->GetList(name_space_ + "/comment_format"));
    }
  }
}

void ReverseLookupFilter::Initialize() {
  initialized_ = true;
  if (!engine_)
    return;
  Ticket ticket(engine_, name_space_);
  if (auto c = ReverseLookupDictionary::Require("reverse_lookup_dictionary")) {
    rev_dict_.reset(c->Create(ticket));
    if (rev_dict_ && !rev_dict_->Load()) {
      rev_dict_.reset();
    }
  }
}

an<Translation> ReverseLookupFilter::Apply(an<Translation> translation,
                                           CandidateList* candidates) {
  if (!initialized_) {
    Initialize();
  }
  if (!rev_dict_) {
    return translation;
  }
  return New<ReverseLookupFilterTranslation>(translation, this);
}

bool ReverseLookupFilter::AppliesToSegment(Segment* segment) {
  if (!TagsMatch(segment))
    return false;
  if (show_if_input_contains_.empty())
    return true;
  // Segment 只记起止偏移，输入文本在 Context 里（engine.cc 里翻译时用的
  // segments->input() 正是从它 Reset 来的，见 ConcreteEngine::Compose）。
  // 任意位置含 z 都触发：首位 z 是拼音反查（zni），中间位 z 是万能键（tzfu），
  // 两种情况都要显示编码；平时不含 z 的输入完全不挂 filter，界面干净。
  if (!engine_ || !segment)
    return false;
  if (Context* ctx = engine_->context()) {
    const string& input = ctx->input();
    if (segment->start <= segment->end && segment->end <= input.length()) {
      string frag =
          input.substr(segment->start, segment->end - segment->start);
      return frag.find(show_if_input_contains_) != string::npos;
    }
  }
  return false;
}

void ReverseLookupFilter::Process(const an<Candidate>& cand) {
  if (!cand->comment().empty() && !(overwrite_comment_ || append_comment_))
    return;
  auto phrase = As<Phrase>(Candidate::GetGenuineCandidate(cand));
  if (!phrase)
    return;
  string codes;
  if (rev_dict_->ReverseLookup(phrase->text(), &codes)) {
    comment_formatter_.Apply(&codes);
    if (!codes.empty()) {
      if (overwrite_comment_ || cand->comment().empty()) {
        phrase->set_comment(codes);
      } else {
        phrase->set_comment(cand->comment() + " " + codes);
      }
    }
  }
}

}  // namespace rime
