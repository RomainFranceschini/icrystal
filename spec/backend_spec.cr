require "./spec_helper"

describe ICrystal do
  describe "backend" do
    it "evals" do
      backend = ICrystal::ICRBackend.new
      result = backend.eval("1 + 2", false)
      result.should be_a(Icr::ExecutionResult)

      result = result.as(Icr::ExecutionResult)
      result.success?.should be_true

      result.value.should eq "3\n"
      result.output.should eq ""
    end

    it "returns syntax errors" do
      backend = ICrystal::ICRBackend.new
      result = backend.eval("a = [1", false)
      result.should be_a(Icr::SyntaxCheckResult)

      result = result.as(Icr::SyntaxCheckResult)
      result.status.should eq :unexpected_eof
    end
  end
end
