require("tests/testsuite")

-- Ensure we start with a clean document set.
ResetDocumentSet()

-- 1) In-paragraph comments ("++") and bracket sequences ([...]) are excluded.
Cmd.InsertStringIntoParagraph("hello world ++ this is a comment")
AssertEquals(2, CountParagraphWords(Document[1]))

Cmd.SplitCurrentParagraph()
Cmd.InsertStringIntoParagraph("normal [ignore this] word")
AssertEquals(2, CountParagraphWords(Document[2]))

-- 2) Document-scoped totals reflect per-paragraph rules.
AssertEquals(4, GetLiveDocumentWordCount(Document))
AssertEquals(4, GetDocumentSetWordCount())

-- Add a second document and verify summary races.
DocumentSet:addDocument(CreateDocument(), "second")
DocumentSet:setCurrent("second")

Cmd.InsertStringIntoParagraph("alpha beta [skip this] gamma ++ now-comment")
AssertEquals(3, CountParagraphWords(Document[1]))

AssertEquals(3, GetLiveDocumentWordCount(Document))
AssertEquals(7, GetDocumentSetWordCount())

-- 4) Daily tracking increments/decrements with changes.
local baseline = GetDailyWordCount()
Cmd.InsertStringIntoParagraph(" newword")
AssertEquals(baseline + 1, GetDailyWordCount())
Cmd.Undo()
AssertEquals(baseline, GetDailyWordCount())

-- 4b) Explicit deletion of typed words updates counts.
Cmd.InsertStringIntoParagraph("zero one two")
AssertEquals(3, CountParagraphWords(Document[1]))
Cmd.DeletePreviousChar() -- Remove last character until word removed
Cmd.DeletePreviousChar()
Cmd.DeletePreviousChar()
Cmd.DeletePreviousChar()
Cmd.DeletePreviousChar()
Cmd.DeletePreviousChar()

-- after removing "two", 1/3 words remain, plus no comments
AssertEquals(1, CountParagraphWords(Document[1]))

-- 5) Battle queue word count should use live document count and clear on defeat.
ClearMonsterQueue()
SetMonsterQueue({{ name = "Test Monster", target_word_count = 2 }})
ResetDocumentSet() -- clear prior text, to control from 0.
Cmd.InsertStringIntoParagraph("one two")
AssertEquals(0, #GetMonsterQueue())
AssertEquals(2, GetMonsterQueueState().wordsTyped)

-- Validate final totals after the defeat interaction.
AssertEquals(2, GetLiveDocumentWordCount(Document))
AssertEquals(2, GetDocumentSetWordCount())

