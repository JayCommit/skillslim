import contextlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from skillslim.cli import main
from skillslim.lint import lint_skill


class SkillslimTests(unittest.TestCase):
    def setUp(self):
        # Keep test artifacts inside the standalone project.
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1])
        self.root = Path(self.temp.name)
        self.skill = self.root / "test-skill"
        self.skill.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def write(self, body="Check the result before returning it."):
        entry = self.skill / "SKILL.md"
        entry.write_text("---\nname: test-skill\ndescription: Review supplied test results.\n---\n\n" + body, encoding="utf-8")
        return entry

    def invoke(self, args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            status = main(args)
        return status, output.getvalue()

    def test_small_skill_needs_no_support_folders(self):
        self.write()
        self.assertEqual(lint_skill(self.skill).findings, [])

    def test_size_boundaries_and_strict_exit(self):
        entry = self.write("Review " * 150)
        estimate = lint_skill(self.skill).estimated_tokens
        self.assertEqual(lint_skill(self.skill, estimate, estimate).findings, [])
        report = lint_skill(self.skill, 1, estimate)
        self.assertEqual(report.findings[0].severity, "warning")
        self.assertEqual(self.invoke(["lint", str(entry), "--warn-tokens", "1"])[0], 0)
        self.assertEqual(self.invoke(["lint", str(entry), "--warn-tokens", "1", "--strict"])[0], 1)
        self.assertEqual(lint_skill(self.skill, 1, 2).findings[0].severity, "error")

    def test_reachable_nested_references_and_cycles(self):
        self.write("For failures, read [guide](references/a.md).")
        refs = self.skill / "references"
        refs.mkdir()
        (refs / "a.md").write_text("Read [details](b.md).", encoding="utf-8")
        (refs / "b.md").write_text("See [guide](a.md).", encoding="utf-8")
        self.assertEqual(lint_skill(self.skill).findings, [])

    def test_missing_orphan_and_escaping_links(self):
        self.write("Read [missing](references/missing.md) or [outside](../outside.md).")
        refs = self.skill / "references"
        refs.mkdir()
        (refs / "orphan.md").write_text("Unused detail", encoding="utf-8")
        rules = {f.rule for f in lint_skill(self.skill).findings}
        self.assertEqual(rules, {"SL300", "SL301", "SL302"})

    def test_links_in_fences_and_remote_links_are_ignored(self):
        self.write("~~~md\n[example](missing.md)\n~~~\nSee [web](https://example.com) and [section](#core).")
        self.assertEqual(lint_skill(self.skill).findings, [])
        self.write("```text\n```not-a-closing-fence\n[example](missing.md)\n```\nCheck output.")
        self.assertEqual(lint_skill(self.skill).findings, [])

    def test_reference_style_links_and_url_encoded_paths(self):
        self.write("For detail, read [guide][ref].\n[ref]: <references/a%20b.md>\nRead [version](references/guide(v2).md).")
        refs = self.skill / "references"
        refs.mkdir()
        (refs / "a b.md").write_text("Detail", encoding="utf-8")
        (refs / "guide(v2).md").write_text("Version detail", encoding="utf-8")
        self.assertEqual(lint_skill(self.skill).findings, [])

    def test_non_actionable_and_bulk_load_advice(self):
        self.write("## Background\nA long story.\nAlways load all references.\n```text\n" + "example\n" * 25 + "```")
        self.assertEqual({f.rule for f in lint_skill(self.skill).findings}, {"SL200", "SL201", "SL202"})
        self.write("Do not always load all references.\nNever say you must read every file.")
        self.assertEqual(lint_skill(self.skill).findings, [])

    def test_missing_frontmatter_body_and_invalid_encoding(self):
        entry = self.write()
        entry.write_text("# No metadata", encoding="utf-8")
        self.assertIn("SL001", {f.rule for f in lint_skill(self.skill).findings})
        self.write("")
        self.assertIn("SL001", {f.rule for f in lint_skill(self.skill).findings})
        for description in ("", "|\n", "# missing"):
            entry.write_text(f"---\nname: test-skill\ndescription: {description}\n---\nCheck output.", encoding="utf-8")
            self.assertIn("SL001", {f.rule for f in lint_skill(self.skill).findings})
        entry.write_text("---\nname: test-skill\ndescription: >-\n  Review test results.\n---\nCheck output.", encoding="utf-8")
        self.assertEqual(lint_skill(self.skill).findings, [])
        entry.write_bytes(b"\xff\xfe")
        self.assertEqual(lint_skill(self.skill).findings[0].rule, "SL000")

    def test_init_is_bundled_and_will_not_overwrite(self):
        target = self.root / "new-skill"
        self.assertEqual(self.invoke(["init", str(target)])[0], 0)
        self.assertEqual(lint_skill(target).findings, [])
        original = (target / "SKILL.md").read_bytes()
        self.assertEqual(self.invoke(["init", str(target)])[0], 2)
        self.assertEqual((target / "SKILL.md").read_bytes(), original)

    def test_recursive_json_and_missing_entrypoint(self):
        self.write()
        ignored = self.root / ".venv"
        ignored.mkdir()
        (ignored / "SKILL.md").write_text("invalid ignored skill", encoding="utf-8")
        status, output = self.invoke(["lint", str(self.root), "--recursive", "--format", "json"])
        self.assertEqual(status, 0)
        self.assertEqual(len(json.loads(output)["reports"]), 1)
        status, output = self.invoke(["lint", str(self.root / "absent"), "--format", "json"])
        self.assertEqual(status, 1)
        self.assertEqual(json.loads(output)["reports"][0]["findings"][0]["rule"], "SL000")
        self.assertTrue(json.loads(output)["reports"][0]["path"].endswith("SKILL.md"))

    def test_symlink_entry_cannot_import_external_rules(self):
        outside = self.root / "outside.md"
        outside.write_text("External instructions", encoding="utf-8")
        try:
            (self.skill / "SKILL.md").symlink_to(outside)
        except OSError:
            self.skipTest("Symlink creation is unavailable on this host")
        self.assertEqual(lint_skill(self.skill).findings[0].rule, "SL300")

    def test_compare_reports_entrypoint_estimate(self):
        baseline = self.root / "baseline.md"
        baseline.write_text("abcd" * 100, encoding="utf-8")
        slim = self.write("Check output.")
        status, output = self.invoke(["compare", str(baseline), str(slim)])
        self.assertEqual(status, 0)
        report = json.loads(output)
        self.assertEqual(report["baseline_estimated_tokens"], 100)
        self.assertGreater(report["entrypoint_reduction_percent"], 50)
        slim.write_text(" \n", encoding="utf-8")
        with self.assertRaises(SystemExit) as error:
            self.invoke(["compare", str(baseline), str(slim)])
        self.assertEqual(error.exception.code, 2)

    def test_standalone_copy_works_without_parent_repository(self):
        target = self.root / "isolated"
        target.mkdir()
        copy = target / "release-notes"
        shutil.copytree(Path(__file__).resolve().parents[1] / "examples" / "release-notes", copy)
        self.assertEqual(lint_skill(copy).findings, [])


if __name__ == "__main__":
    unittest.main()
